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

pub fn parseLuaFile(
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
            if (pos >= content.len or content[pos] != '"') continue;
            pos += 1;
            const path_start = pos;
            while (pos < content.len and content[pos] != '"') {
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
    return results.toOwnedSlice(allocator);
}
