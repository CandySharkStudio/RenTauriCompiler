const std = @import("std");
const builtin = @import("builtin");
fn eq(a: []const u8, b: []const u8) bool {
    return a.len == b.len and std.mem.eql(u8, a, b);
}
fn panicHandler(msg: []const u8, ret_addr: ?usize) noreturn {
    @branchHint(.cold);
    std.debug.print("Error: {s}\n", .{msg});
    std.debug.defaultPanic(msg, ret_addr);
}

const default_aes_key: []const u8 = "Nim3VGmCjDBKMnaDqOX7RrsbP7/bz3zochCDuMuWMNI=";
pub const panic = std.debug.FullPanic(panicHandler);
fn showHelp() void {
    const help_msg =
        \\Ren'Tauri Compiler
        \\
        \\Usage: rtc [commands]
        \\       rtc [options] <source>.lua
        \\       rtc [help option]
        \\Commands:
        \\    init    在当前目录下初始化一个 main.lua 文件！
        \\
        \\Options:
        \\    -o, --output <NAME>.<.rrs>    输出最终编译产物
        \\    -k, --key <AES_KEY>           手动指定 AES Key
        \\    -q, --quiet                   静默输出（不输出命令行日志）
        \\
        \\Help Option:
        \\    -v, --version   输出当前版本
        \\    -h, --help      输出帮助
        \\
    ;
    std.debug.print("{s}\n", .{help_msg});
}
fn setFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    _ = try file.writeAll(content);
}
pub fn main() !void {
    var original_cp: u32 = 0;
    if (builtin.os.tag == .windows) {
        original_cp = std.os.windows.kernel32.GetConsoleOutputCP();
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
    defer if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(original_cp);
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len <= 1) {
        showHelp();
        var buffer: [1024]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&buffer);
        var stdin = &reader.interface;
        _ = try stdin.takeDelimiterExclusive('\n');
    } else {
        if (std.mem.eql(u8, args[1], "init")) {
            if (args.len > 2) {
                @panic("init has more than 2 parameter!");
            } else {
                try setFile("main.lua",
                    \\11
                );
            }
        } else if (eq(args[1], "-h") or eq(args[1], "--help")) {
            showHelp();
        } else if (eq(args[1], "-v") or eq(args[1], "--version")) {
            std.debug.print("version: 1.0.0", .{});
        } else {
            const lua_path = args[1];
            const lua_ext = std.fs.path.extension(lua_path);
            if (!eq(lua_ext, ".lua")) {
                @panic("first parameter extension must be .lua file!");
            }
            var i: usize = 2;
            var quiet: bool = false;
            var output: []const u8 = "main.rrs";
            var aes_key = default_aes_key;
            while (i < args.len) : (i += 1) {
                if (eq(args[i], "-q") or eq(args[i], "--quiet")) {
                    quiet = true;
                } else if (eq(args[i], "-o") or eq(args[i], "--output")) {
                    if (i + 1 >= args.len) @panic("The -o parameter must be follow by another arguments!");
                    const op_ext = std.fs.path.extension(args[i + 1]);
                    if (eq(op_ext, ".rrs")) {
                        output = args[i + 1];
                    } else {
                        output = try std.fmt.allocPrint(arena.allocator(), "{s}.rrs", .{args[i + 1]});
                    }
                    i += 1;
                } else if (eq(args[i], "-k") or eq(args[i], "--key")) {
                    if (i + 1 >= args.len) @panic("The -k parameter must be follow by another arguments!");
                    aes_key = args[i + 1];
                    i += 1;
                }
            }
            std.debug.print("LuaPath: {s}\nIsQuiet: {}\nOutputFile: {s}\nAES_Key: {s}", .{ lua_path, quiet, output, aes_key });
        }
    }
}
