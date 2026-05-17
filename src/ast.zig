const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
pub const CopywritingStruct = struct {
    // 全局定义
    define: std.StringHashMap(std.json.Value),
    // 部分二进制资源
    resource: std.StringHashMap([]const u8),
    // 当前翻译
    translate: std.StringHashMap(std.StringHashMap([]const u8)),
    // 当前样式表
    style: std.StringHashMap([]const u8),
    // 当前控件表
    components: std.ArrayList(std.StringHashMap(std.json.Value)),
    // 最终的文案代码
    copywriting: std.json.Value,
    // 自定义 JSON 解析器
    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        try jw.beginObject();

        // 1. 序列化 define
        try jw.objectField("define");
        try jw.beginObject();
        var def_iter = self.define.iterator();
        while (def_iter.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            try jw.write(entry.value_ptr.*);
        }
        try jw.endObject();

        // 2. 序列化 resource
        try jw.objectField("resource");
        try jw.beginObject();
        var res_iter = self.resource.iterator();
        while (res_iter.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            try jw.write(entry.value_ptr.*);
        }
        try jw.endObject();

        // 3. 序列化 translate (嵌套 HashMap)
        try jw.objectField("translate");
        try jw.beginObject();
        var trans_iter = self.translate.iterator();
        while (trans_iter.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            // 内层 HashMap
            try jw.beginObject();
            var inner_iter = entry.value_ptr.*.iterator();
            while (inner_iter.next()) |inner_entry| {
                try jw.objectField(inner_entry.key_ptr.*);
                try jw.write(inner_entry.value_ptr.*);
            }
            try jw.endObject();
        }
        try jw.endObject();

        // 4. 序列化 style
        try jw.objectField("style");
        try jw.beginObject();
        var style_iter = self.style.iterator();
        while (style_iter.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            try jw.write(entry.value_ptr.*);
        }
        try jw.endObject();

        // 5. 序列化 components (ArrayList)
        try jw.objectField("components");
        try jw.beginArray();
        for (self.components.items) |comp_map| {
            try jw.beginObject();
            var comp_iter = comp_map.iterator();
            while (comp_iter.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try jw.write(entry.value_ptr.*);
            }
            try jw.endObject();
        }
        try jw.endArray();

        // 6. 序列化 copywriting
        try jw.objectField("copywriting");
        try jw.write(self.copywriting);

        try jw.endObject();
    }
};
pub const ResultStruct = struct {
    binary_name: std.ArrayList([]const u8),
    copywriting: CopywritingStruct,
    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        try jw.beginObject();

        // 序列化 binary_name
        try jw.objectField("binary_name");
        try jw.beginArray();
        for (self.binary_name.items) |name| {
            try jw.write(name);
        }
        try jw.endArray();

        // 序列化 copywriting
        // 因为 CopywritingStruct 已经实现了 jsonStringify，这里直接 write 即可
        try jw.objectField("copywriting");
        try jw.write(self.copywriting);

        try jw.endObject();
    }
};
var copywriting_doc: ResultStruct = undefined;

pub fn ast(
    allocator: std.mem.Allocator,
    lua_content: []const u8,
) !ResultStruct {
    var lua = try Lua.init(allocator);
    defer lua.deinit();
    copywriting_doc = ResultStruct{
        .binary_name = try std.ArrayList([]const u8).initCapacity(allocator, std.math.maxInt(u8)),
        .copywriting = CopywritingStruct{
            .define = std.StringHashMap(std.json.Value).init(allocator),
            .resource = std.StringHashMap([]const u8).init(allocator),
            .translate = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
            .style = std.StringHashMap([]const u8).init(allocator),
            .components = try std.ArrayList(std.StringHashMap(std.json.Value)).initCapacity(allocator, std.math.maxInt(u8)),
            .copywriting = .null,
        },
    };
    const c_lua_content = try allocator.dupeZ(u8, lua_content);
    defer allocator.free(c_lua_content);
    try lua.doString(c_lua_content);
    return copywriting_doc;
}
