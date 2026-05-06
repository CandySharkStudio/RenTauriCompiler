const std = @import("std");
const stripLuaComments = @import("parser.zig").stripLuaComments;
const print = @import("util.zig").print;

const Aes256 = std.crypto.core.aes.Aes256;

const BLOCK_SIZE: usize = 16;
// 内存块大小
const BUFFER_SIZE: usize = 128 * 1024;
// 文件头信息（路径+大小）
const FileMeta = struct {
    path: []const u8,
    size: u64,
};
// 文件源（文件+内存）
const DataSource = union(enum) {
    file: std.fs.File,
    memory: []const u8,
};
// 修复 Base64
pub fn base64DecodeFixed(input: []const u8) ![32]u8 {
    const Decoder = std.base64.standard.Decoder;
    var result: [32]u8 = undefined;
    const size = try Decoder.calcSizeForSlice(input);
    if (size != 32) {
        return error.InvalidPadding;
    }
    try Decoder.decode(&result, input);
    if (result.len != 32) return error.InvalidPadding;
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
// 流式加密代码（流式加密采取读一点加密一点的原则，即使是面对超级大的文件也能无比从容的面对！）
pub fn streamEncryptFiles(allocator: std.mem.Allocator, out_file: std.fs.File, files: []const []const u8, key: [32]u8, iv1: [16]u8, iv2: [16]u8) !void {
    var metas = try std.ArrayList(FileMeta).initCapacity(allocator, std.math.maxInt(u8));
    defer metas.deinit(allocator);
    var sources = try std.ArrayList(DataSource).initCapacity(allocator, std.math.maxInt(u8));
    defer {
        for (sources.items) |src| {
            switch (src) {
                .file => |f| f.close(),
                .memory => |data| allocator.free(data), // 释放预处理文本的内存
            }
        }
        sources.deinit(allocator);
    }
    var total_data_size: u64 = 0;
    for (files) |file_path| {
        // 直接判断后缀看看这个是否需要去除注释。
        if (std.mem.endsWith(u8, file_path, ".lua")) {
            const raw_data = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
            errdefer allocator.free(raw_data);
            const cleaned_data = try stripLuaComments(raw_data, allocator);
            allocator.free(raw_data);
            try metas.append(allocator, .{ .path = file_path, .size = cleaned_data.len });
            try sources.append(allocator, .{ .memory = cleaned_data });
            total_data_size += cleaned_data.len;
        } else {
            // --- 二进制逻辑：只拿元数据，准备流式句柄 ---
            const stat = try std.fs.cwd().statFile(file_path);
            const file = try std.fs.cwd().openFile(file_path, .{});
            try metas.append(allocator, .{ .path = file_path, .size = stat.size });
            try sources.append(allocator, .{ .file = file });
            total_data_size += stat.size;
        }
    }
    // 计算 PKCS7 填充
    const pad_size: u8 = if (total_data_size % BLOCK_SIZE == 0) BLOCK_SIZE else @intCast(BLOCK_SIZE - (total_data_size % BLOCK_SIZE));
    const total_encrypted_size = total_data_size + pad_size;
    // 先加密写出所有文件基本头信息。
    var dir_buffer = try std.ArrayList(u8).initCapacity(allocator, std.math.maxInt(u8));
    defer dir_buffer.deinit(allocator);
    const dir_writer = dir_buffer.writer(allocator);
    try dir_writer.writeInt(u32, @intCast(metas.items.len), .little);
    for (metas.items) |meta| {
        try dir_writer.writeInt(u32, @intCast(meta.path.len), .little);
        try dir_writer.writeAll(meta.path);
        try dir_writer.writeInt(u64, meta.size, .little);
    }
    const dir_pad_size: u8 = if (dir_buffer.items.len % BLOCK_SIZE == 0) BLOCK_SIZE else @intCast(BLOCK_SIZE - (dir_buffer.items.len % BLOCK_SIZE));
    // 拷贝内存
    var dir_padded = try allocator.alloc(u8, dir_buffer.items.len + dir_pad_size);
    defer allocator.free(dir_padded);
    @memcpy(dir_padded[0..dir_buffer.items.len], dir_buffer.items);
    @memset(dir_padded[dir_buffer.items.len..], dir_pad_size);

    // 为 iv1 分配独立内存
    const dir_ct_len = dir_padded.len;
    var dir_encrypted = try allocator.alloc(u8, BLOCK_SIZE + dir_ct_len);
    defer allocator.free(dir_encrypted);
    @memcpy(dir_encrypted[0..BLOCK_SIZE], &iv1);

    // 将 dir_pad_size 以及填充后的数字添加到列表。
    // 开始使用 iv1 加密文件头信息
    const aes1 = Aes256.initEnc(key);
    var prev1: [BLOCK_SIZE]u8 = iv1;
    for (0..dir_ct_len / BLOCK_SIZE) |i| {
        const offset = i * BLOCK_SIZE;
        var block: [BLOCK_SIZE]u8 = undefined;
        for (0..BLOCK_SIZE) |j| {
            block[j] = dir_padded[offset + j] ^ prev1[j];
        }
        aes1.encrypt(&block, &block);
        @memcpy(dir_encrypted[BLOCK_SIZE + offset ..][0..BLOCK_SIZE], &block);
        prev1 = block;
    }
    // 写入文件头。
    var buf_dir_encrypted: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf_dir_encrypted, @intCast(dir_encrypted.len), .little);
    try out_file.writeAll(&buf_dir_encrypted);
    try out_file.writeAll(dir_encrypted);
    // 写入 iv2
    try out_file.writeAll(&iv2);
    // 随后再写入真实数据。
    const aes2 = Aes256.initEnc(key);
    var prev_block: [BLOCK_SIZE]u8 = iv2;
    var buf: [BUFFER_SIZE]u8 = undefined;
    var ct_buf: [BUFFER_SIZE]u8 = undefined;
    var global_read: u64 = 0;
    var current_idx: usize = 0;
    // 内存读取专用的偏移量指针
    var mem_offset: usize = 0;
    print("流式分析已完成 (总数据: {} B)，开始流式加密...\n", .{total_data_size});
    // 统一的流式加密循环（下列纯使用计算。。）
    while (global_read < total_encrypted_size) {
        var buf_offset: usize = 0;
        while (buf_offset < BUFFER_SIZE) {
            if (global_read < total_data_size) {
                const remaining_in_buf = BUFFER_SIZE - buf_offset;
                const current_source = &sources.items[current_idx];
                var bytes_read: usize = 0;
                // 根据源类型，采取不同的读取策略
                switch (current_source.*) {
                    .file => |*f| {
                        bytes_read = f.read(buf[buf_offset..][0..remaining_in_buf]) catch return error.ReadFailed;
                    },
                    .memory => |data| {
                        const left_to_read = data.len - mem_offset;
                        const to_read = @min(left_to_read, remaining_in_buf);
                        if (to_read > 0) {
                            @memcpy(buf[buf_offset..][0..to_read], data[mem_offset..][0..to_read]);
                            mem_offset += to_read;
                        }
                        bytes_read = to_read;
                    },
                }
                if (bytes_read == 0) {
                    // 当前源读完了，切换到下一个源
                    mem_offset = 0; // 重置内存偏移量
                    current_idx += 1;
                } else {
                    buf_offset += bytes_read;
                    global_read += bytes_read;
                }
            } else {
                // PKCS7 填充逻辑不变
                const pad_left = total_encrypted_size - global_read;
                if (pad_left == 0) break;
                const pad_to_write = @min(pad_left, BUFFER_SIZE - buf_offset);
                @memset(buf[buf_offset..][0..pad_to_write], pad_size);
                buf_offset += pad_to_write;
                global_read += pad_to_write;
            }
        }
        // 此处开始加密！
        for (0..buf_offset / BLOCK_SIZE) |i| {
            const offset = i * BLOCK_SIZE;
            for (0..BLOCK_SIZE) |j| {
                ct_buf[offset + j] = buf[offset + j] ^ prev_block[j];
            }
            var block: [BLOCK_SIZE]u8 = ct_buf[offset..][0..BLOCK_SIZE].*;
            aes2.encrypt(&block, &block);
            ct_buf[offset..][0..BLOCK_SIZE].* = block;
            prev_block = block;
        }
        try out_file.writeAll(ct_buf[0..buf_offset]);
    }
}
