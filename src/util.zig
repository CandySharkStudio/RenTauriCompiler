const std = @import("std");
pub fn eq(a: []const u8, b: []const u8) bool {
    return a.len == b.len and std.mem.eql(u8, a, b);
}

pub fn setFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    _ = try file.writeAll(content);
}
pub fn print(comptime msg: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    writer.interface.print(msg, args) catch {};
    writer.interface.flush() catch {};
}
pub fn input() ![]u8 {
    var buffer: [1024]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&buffer);
    const output = try reader.interface.takeDelimiterExclusive('\n');
    return output;
}
pub fn getFile(path: []const u8) []const u8 {
    return path;
}
