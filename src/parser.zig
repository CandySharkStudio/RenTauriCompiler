const std = @import("std");

const TARGET_FUNCTIONS = [_][]const u8{
    "embedLuaFile",
    "Image",
    "Audio",
    "Video",
    "Font",
};
fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}
fn skipWhitespace(content: []const u8, start: usize) usize {
    var i = start;
    while (i < content.len and isWhitespace(content[i])) {
        i += 1;
    }
    return i;
}

fn isIdentifierChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '_';
}

fn countLongBracketOpen(s: []const u8) i32 {
    if (s.len < 2 or s[0] != '[') return -1;
    var level: i32 = 0;
    var i: usize = 1;
    while (i < s.len and s[i] == '=') {
        level += 1;
        i += 1;
    }
    if (i < s.len and s[i] == '[') return level;
    return -1;
}

fn matchLongBracketClose(s: []const u8, level: i32) bool {
    if (s.len < 2 or s[0] != ']') return false;
    var i: usize = 1;
    var matched: i32 = 0;
    while (i < s.len and s[i] == '=') {
        matched += 1;
        i += 1;
    }
    return i < s.len and s[i] == ']' and matched == level;
}

/// 去除所有注释，保留字符串内容
fn stripCommentsPass(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var output = try std.ArrayList(u8).initCapacity(allocator, std.math.maxInt(u8));
    var i: usize = 0;
    while (i < input.len) {
        // 单行注释
        if (input[i] == '-' and i + 1 < input.len and input[i + 1] == '-') {
            i += 2;
            // 如果是长注释
            if (i < input.len and input[i] == '[') {
                const level = countLongBracketOpen(input[i..]);
                if (level >= 0) {
                    const level_usize: usize = @intCast(level);
                    i += level_usize + 2;
                    while (i < input.len) {
                        if (input[i] == ']' and matchLongBracketClose(input[i..], level)) {
                            i += level_usize + 2; // 跳过 ]=*]
                            break;
                        }
                        i += 1;
                    }
                    continue;
                }
            }
            while (i < input.len and input[i] != '\n') {
                i += 1;
            }
            continue;
        }
        // 单双引号里的 -- 注释
        if (input[i] == '"') {
            try output.append(allocator, '"');
            i += 1;
            while (i < input.len and input[i] != '"') {
                if (input[i] == '\\' and i + 1 < input.len) {
                    try output.append(allocator, input[i]);
                    i += 1;
                }
                try output.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) {
                try output.append(allocator, '"');
                i += 1;
            }
            continue;
        }
        if (input[i] == '\'') {
            try output.append(allocator, '\'');
            i += 1;
            while (i < input.len and input[i] != '\'') {
                if (input[i] == '\\' and i + 1 < input.len) {
                    try output.append(allocator, input[i]);
                    i += 1;
                }
                try output.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) {
                try output.append(allocator, '\'');
                i += 1;
            }
            continue;
        }
        // 匹配 [[]] 的字符串，包括里面有 = 号时的 -- 注释不予去除！
        if (input[i] == '[') {
            const level = countLongBracketOpen(input[i..]);
            if (level >= 0) {
                const level_usize: usize = @intCast(level);
                const open_len = level_usize + 2;
                try output.appendSlice(allocator, input[i .. i + open_len]);
                i += open_len;
                while (i < input.len) {
                    if (input[i] == ']' and matchLongBracketClose(input[i..], level)) {
                        const close_len = level_usize + 2;
                        try output.appendSlice(allocator, input[i .. i + close_len]);
                        i += close_len;
                        break;
                    }
                    try output.append(allocator, input[i]);
                    i += 1;
                }
                continue;
            }
        }
        try output.append(allocator, input[i]);
        i += 1;
    }

    return try output.toOwnedSlice(allocator);
}

// 去除空白行
fn stripBlankLines(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var output = try std.ArrayList(u8).initCapacity(allocator, std.math.maxInt(u8));
    var line_start: usize = 0;
    var i: usize = 0;
    while (i <= input.len) {
        if (i == input.len or input[i] == '\n') {
            const line = input[line_start..i];
            var is_blank = true;
            for (line) |c| {
                if (!isWhitespace(c)) {
                    is_blank = false;
                    break;
                }
            }
            if (!is_blank) {
                try output.appendSlice(allocator, line);
                if (i < input.len) try output.append(allocator, '\n');
            }
            line_start = i + 1;
        }
        i += 1;
    }
    // 去除末尾可能出现的空行
    if (output.items.len > 0 and output.items[output.items.len - 1] == '\n') {
        _ = output.pop();
    }
    return try output.toOwnedSlice(allocator);
}

pub fn stripLuaComments(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const no_comments = try stripCommentsPass(input, allocator);
    defer allocator.free(no_comments);
    return stripBlankLines(no_comments, allocator);
}
pub fn parseLuaFile(
    raw_path: []const u8,
    content: []const u8,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    var results = try std.ArrayList([]const u8).initCapacity(allocator, std.math.maxInt(u8));
    var idx: usize = 0;
    while (idx < content.len) {
        var matched: bool = false;
        for (TARGET_FUNCTIONS) |func_name| {
            // 这里已经在指针处进行判断了！
            if (!std.mem.startsWith(u8, content[idx..], func_name)) {
                continue;
            }
            // 定义一个 name_end 用来表示当前指针指向的 funcname 末尾。
            const name_end = idx + func_name.len;
            if (idx > 0 and isIdentifierChar(content[idx - 1])) {
                continue;
            }
            if (name_end < content.len and isIdentifierChar(content[name_end])) {
                continue;
            }
            var pos = skipWhitespace(content, name_end);
            if (pos >= content.len or content[pos] != '(') continue;
            pos += 1;
            pos = skipWhitespace(content, pos);
            if (pos >= content.len) continue;
            const quote_char = content[pos];
            // 需要判断单双引号
            if (quote_char != '\"' and quote_char != '\'') continue;
            pos += 1;
            const path_start = pos;
            while (pos < content.len and content[pos] != quote_char) {
                pos += 1;
            }
            if (pos >= content.len) continue;
            const file_path = content[path_start..pos];
            try results.append(allocator, file_path);
            idx = pos;
            matched = true;
            break;
        }
        if (!matched) {
            idx += 1;
        }
    }
    try results.append(allocator, raw_path);
    return results.toOwnedSlice(allocator);
}
