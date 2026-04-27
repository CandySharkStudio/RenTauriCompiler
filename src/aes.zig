const std = @import("std");
const stripLuaComments = @import("parser.zig").stripLuaComments;
const Aes256 = std.crypto.core.aes.Aes256;
const print = @import("util.zig").print;
// 以 pkcs7 填充
pub fn pkcs7Pad(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const block_size: usize = 16;
    const pad_len: u8 = @intCast(block_size - (data.len % block_size));
    const padded_len = data.len + pad_len;
    const padded = try allocator.alloc(u8, padded_len);
    @memcpy(padded[0..data.len], data);
    @memset(padded[data.len..], pad_len);
    return padded;
}
// 以 pkcs7 去填充
fn pkcs7Unpad(data: []const u8) ![]const u8 {
    if (data.len == 0 or data.len % 16 != 0) return error.InvalidPadding;
    const pad_value = data[data.len - 1];
    if (pad_value == 0 or pad_value > 16) return error.InvalidPadding;
    for (data[data.len - pad_value ..]) |byte| {
        if (byte != pad_value) return error.InvalidPadding;
    }
    return data[0 .. data.len - pad_value];
}
// 修复 Base64
pub fn base64DecodeFixed(input: []const u8) ![32]u8 {
    const Decoder = std.base64.standard.Decoder;
    var result: [32]u8 = undefined;
    try Decoder.decode(&result, input);
    return result;
}
// 随机生成密钥
pub fn generateKeyBase64(allocator: std.mem.Allocator) ![]const u8 {
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);
    const Encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, Encoder.calcSize(key.len));
    return Encoder.encode(encoded, &key);
}
// 打包文件
pub fn packFiles(allocator: std.mem.Allocator, files: []const []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, std.math.maxInt(u8));
    defer list.deinit(allocator);
    const writer = list.writer(allocator);

    for (files) |file_path| {
        var data = std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize)) catch |err| {
            print("无法读取文件 {s}: {}\n", .{ file_path, err });
            return err;
        };
        defer allocator.free(data);
        // 首先去除一遍所有注释
        data = try stripLuaComments(data, allocator);
        // 写入路径长度
        try writer.writeInt(u32, @intCast(file_path.len), .little);
        // 写入路径
        try writer.writeAll(file_path);
        // 写入数据长度
        try writer.writeInt(u32, @intCast(data.len), .little);
        // 写入数据
        try writer.writeAll(data);
    }
    return list.toOwnedSlice(allocator);
}
// 开始加密
pub fn aes256CbcEncrypt(allocator: std.mem.Allocator, plaintext: []const u8, key: [32]u8, iv: [16]u8) ![]u8 {
    if (plaintext.len % 16 != 0) return error.InvalidPlaintextLength;
    const aes = Aes256.initEnc(key);
    const ciphertext = try allocator.alloc(u8, plaintext.len);
    errdefer allocator.free(ciphertext);

    var prev: [16]u8 = iv;
    for (0..plaintext.len / 16) |block_idx| {
        const offset = block_idx * 16;
        var block: [16]u8 = undefined;
        for (0..16) |j| block[j] = plaintext[offset + j] ^ prev[j];
        aes.encrypt(&block, &block);
        @memcpy(ciphertext[offset..][0..16], &block);
        prev = block;
    }
    return ciphertext;
}
