const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const aes = @import("aes.zig");
const eq = util.eq;
const setFile = util.setFile;
const getFile = util.getFile;
const print = util.print;
const luaParser = @import("parser.zig").parseLuaFile;
fn panicHandler(msg: []const u8, ret_addr: ?usize) noreturn {
    @branchHint(.cold);
    print("Error: {s}\n", .{msg});
    std.debug.defaultPanic(msg, ret_addr);
}
pub const panic = std.debug.FullPanic(panicHandler);
const default_aes_key: []const u8 = "Nim3VGmCjDBKMnaDqOX7RrsbP7/bz3zochCDuMuWMNI=";
const Aes256 = std.crypto.core.aes.Aes256;
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
    print("{s}\n", .{help_msg});
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
        _ = try util.input();
    } else {
        if (std.mem.eql(u8, args[1], "init")) {
            if (args.len > 2) {
                @panic("init has more than 2 parameter!");
            } else {
                try setFile("main.lua",
                    \\-- 所有资源必须声明在整个 main.lua 的开头！否则无法被编译器解析！
                    \\-- 所有静态资源都必须声明在整个 main.lua 里面，你绝对不能将静态资源声明到别的 .lua 文件里！
                    \\-- 声明资源（第一个参数填路径，第二个参数填 MIME 类型，具体 MIME 格式如下图显示！）
                    \\--[[
                    \\image/gif：GIF图片
                    \\image/png：PNG图片
                    \\image/webp：WebP图片
                    \\image/svg+xml：SVG矢量图
                    \\image/bmp：BMP位图
                    \\image/avif：AVIF图片
                    \\image/apng：APNG动图
                    \\audio/mpeg：MP3音频
                    \\audio/wav：WAV音频
                    \\audio/ogg：OGG音频
                    \\audio/aac：AAC音频
                    \\audio/flac：FLAC无损音频
                    \\audio/webm：WebM音频
                    \\video/mp4：MP4视频
                    \\video/mpeg：MPEG视频
                    \\video/ogg：OGG视频
                    \\video/webm：WebM视频
                    \\video/quicktime：MOV视频
                    \\video/x-msvideo：AVI视频
                    \\font/ttf：TrueType字体
                    \\font/otf：OpenType字体
                    \\font/woff：Web开放字体格式
                    \\font/woff2：WOFF 2.0
                    \\]]
                    \\-- 使用 Image 去声明一个图片文件，当然你也可以用 Base64Image 去声明一个 Base64 源码的图片（
                    \\-- 这里极其不建议使用 Base64，因为这样会导致体积变大。。
                    \\-- 所有背景图建议都搞成 16:9 的大小，例如 1920x1080 或者 2560x1440。
                    \\-- 角色立绘可以搞成竖着的，多大都可以。。因为 RenTauri 会手动帮各位调整！
                    \\local bg = Image("assets/image/Bg.png", "image/png")
                    \\-- Audio 函数用来初始化音乐！
                    \\-- Audio 函数也可以变身成 Base64Audio 去声明一个 Base64 的音乐！
                    \\local bgm = Audio("assets/audio/music.mp3", "audio/mpeg")
                    \\-- 音效建议使用 ogg，音乐建议使用 mp3，仅此而已。。
                    \\local snd = Audio("assets/audio/sound.ogg", "audio/ogg")
                    \\-- 定义字体（Base64Font 也是可以的。。）
                    \\local myFont = Font("assets/fonts/MyFont.ttf", "font/ttf")
                    \\-- 定义视频（视频和 Image 可以一样用！但是只能用来当背景，无法用来当作立绘。。）
                    \\local myvideo = Video("assets/video/video.mp4", "video/mp4")
                    \\-- 下列定义了一个全局常量！DefaultInstance 第一个填变量 ID，这个 ID 必须全局唯一，与 Menu 区分，不然会有 bug。第二个填初始值！
                    \\-- DefaultInstance 只在当前存档有效，设置之后可以通过回退修改。
                    \\local book = DefaultInstance("书本", false)
                    \\-- 你也可以定义一个所有存档通用的全局变量
                    \\-- DefaultGlobal 和 DefaultInstance 唯一的区别就是在它一旦被修改，就无法回退了！并且全存档通用！（哪怕换存档也没用）
                    \\-- 第一个值依旧是 ID，但是可以与上方的 DefaultInstance 不一致。
                    \\local book_global = DefaultGlobal("书本全局", false)
                    \\-- 声明角色（留空则默认为旁白。）
                    \\local George = Character("乔治", "#48ce41")
                    \\local Andrey = Character("安德烈", "#FF9900")
                    \\local Aside = Character("", "")
                    \\-- 引入其他 .lua 文件，可以直接写在这里
                    \\loadFile("scripts/xxx.lua")
                    \\-- 这样可以把 xxx.lua 给包含进来，随后下面即可直接使用 xxx.lua 里的函数！Jump 也可以直接跳转过去。
                    \\-- 你甚至可以把所有【设置 settings.lua】单独设立一个 .lua 文件。随后在 main.lua 里面导入即可！
                    \\-- 但是切记，所有的 Character、Audio、常量等，均需要设置在 loadFile 的上方，不然无法解析！
                    \\
                    \\-- 还有一点，只有 main.lua 里面可以导入资源，别的 .lua 文件不能导入资源！绝对不能导入资源！否则会因为读取不到而报错！
                    \\
                    \\
                    \\-- 文案代码程序一开始时执行的 Start 函数
                    \\-- 这个函数也应该写在 main.lua 里面，不能写在别的 lua 文件里面！
                    \\-- 如果你希望文案代码单独写一个 writer.lua 的话，你可以在这里面写一个 Jump(RealStart)，随后在上方使用 loadFile 引入别的 lua 文件，再然后就直接在函数里写 function RealStart() end 即可！
                    \\function Start()
                    \\    -- 使用 Say 函数去显示对话。
                    \\    -- 在中间使用 Color 函数显示颜色或者字体。
                    \\    -- 【喜欢】变成了红色。
                    \\    Say(George, "你好，我" .. Span("喜欢", {color = "#FF0000"}) .. "你！")
                    \\    -- 【怎么】变成了自定义字体，并且字号是 10 号！
                    \\    Say(Andrey, "你" .. Span("怎么", {font = myFont, size = 10}) .. "了？")
                    \\    -- 使用 Menu 作为选项，第一个值是全局唯一的 key！必须与上方的 DefaultInstance 的所有给区分开！
                    \\    -- 也就是说，第一个值不能与上方 DefaultInstance 的值重复！但是 DefaultGlobal 倒是可以。。
                    \\    Menu("选项1", {
                    \\        -- 以键名做选项名，键值为一个函数。
                    \\        ["你为什么要去？"] = function()
                    \\            Say(George, "我不去你能怎么办？")
                    \\            -- 跳转到 Label2 这个函数（你只能使用 Jump！不能直接使用 Label2() 去跑！）
                    \\            Jump(Label2)
                    \\        end,
                    \\        ["我不去你养我？"] = function()
                    \\            Say(George, "我养你啊！")
                    \\            Jump(Label3)
                    \\        end
                    \\    })
                    \\    -- 由于两个选项均有 Jump，因此底下不会再有任何语句（即使有也不会执行了。）
                    \\end
                    \\-- 名称叫 Label2 的函数！
                    \\function Label2()
                    \\    Say(George, "你为什么要来这里？")
                    \\    Say(Andrey, "我就是要来这里！")
                    \\    Jump(Label4)
                    \\end
                    \\function Label3()
                    \\    Say(George, "好啊！你养我！")
                    \\    Say(Andrey, "那我可以来这里了吧！")
                    \\    Jump(Label4)
                    \\end
                    \\function Label4()
                    \\    Say(Aside, "于是他们过上了没羞没躁的生活~")
                    \\    --[[
                    \\    对应了 renpy 里面的：
                    \\    scene bg
                    \\    ]]
                    \\    -- 下面的 dissolve 也可以写 fade
                    \\    ShowScene(bg, "dissolve")
                    \\    -- 展示 Video 视频可以使用下面的语句，但是这个语句会将背景图片替换掉！
                    \\    -- 如果是 Video 的背景的话，默认的背景音乐是随着全局音乐的大小声去播放的。
                    \\    -- Video 背景不会去除默认的背景音乐，这也可以做双声道。并且默认循环播放！可以设置 1.0、1.0 的渐入渐出！
                    \\    ShowVideo(myvideo, "fade", 1.0, 1.0)
                    \\    --[[
                    \\    对应了 renpy 里面的：
                    \\    show bg at right
                    \\    with fade
                    \\    ]]
                    \\    ShowImage(bg, "fade", "right")
                    \\    -- 肯定还有 HideImage 的啦！
                    \\    -- 在 show 的时候，完全可以照着 renpy 去写的！完全不用纠结这是哪个的噢！
                    \\    HideImage(bg)
                    \\    -- 播放音乐（切记，在整个程序中最多只能有一首背景音乐播放！背景音乐默认循环！）
                    \\    -- 但是可以同时播放多个音效！因此如果你想营造多个不同背景音乐同时播放的话，你可以直接使用 PlaySound！
                    \\    -- 音乐可以设置渐入渐出属性，但是音效不能！下面两个参数分别是渐入和渐出（秒做单位）！
                    \\    PlayMusic(bgm, 1.0, 1.0)
                    \\    -- 每执行一个 PlayMusic 都会使得前一个直接播放结束！
                    \\    -- 暂停音乐！此时没有音乐播放了。。无需参数，上一个音乐会按照 fadeout 自动退出！
                    \\    StopMusic()
                    \\    -- 播放音效！音效可以同时播放很多个！
                    \\    PlaySound(snd)
                    \\    -- Pause 可以停顿几秒！也可以直接写 0 以触发鼠标再次点击才继续执行！
                    \\    Pause(0)
                    \\    Pause(3.0)
                    \\    Jump(Label5)
                    \\end
                    \\
                    \\function Label5()
                    \\    -- 下面写 DefaultInstance 的事！
                    \\    Menu("选项2", {
                    \\        ["设置全局变量"] = function()
                    \\            -- 使用 SetGlobalValue 去修改任何一个全局变量！
                    \\            SetGlobalValue(book_global, true)
                    \\        end,
                    \\        ["设置当前变量"] = function()
                    \\            -- 使用 SetValue 去修改任何一个局部变量！
                    \\            SetValue(book, true)
                    \\        end
                    \\    })
                    \\    -- 下列使用 If 这个函数去判断上述的变量！
                    \\    -- 直接使用 GetValue 去判断即可！当然，上面由于是布尔值，因此这里可以直接不用写后面的 == true。。
                    \\    -- 但是为了让各位理解得好，我还是写吧！
                    \\    -- 第一个值是 true 时执行的语句，第二个值是 false 时执行的语句！
                    \\    If(GetValue(book) == true, function()
                    \\        Say(Aside, "如果你设置了当前变量，那能看到我！")
                    \\    end, function()
                    \\        Say(Aside, "如果你没有设置当前变量，那能看到我！")
                    \\    end)
                    \\    -- 这里得使用 GetGlobalValue 去获取它！
                    \\    If(GetGlobalValue(book_global) == true, function()
                    \\        Say(Aside, "如果你设置了全局变量，那你就能一直看到我了！无论回退多少次都是如此！无论新建任何存档都是如此！")
                    \\    end, function()
                    \\        Say(Aside, "如果你没有设置全局变量，可以回去设置一次再来哦！")
                    \\    end)
                    \\end
                );
            }
        } else if (eq(args[1], "-h") or eq(args[1], "--help")) {
            showHelp();
        } else if (eq(args[1], "-v") or eq(args[1], "--version")) {
            print("version: 1.0.0\n", .{});
        } else {
            const lua_path = args[1];
            const lua_ext = std.fs.path.extension(lua_path);
            if (!eq(lua_ext, ".lua")) {
                @panic("first parameter extension must be .lua file!");
            }
            var i: usize = 2;
            var noquiet: bool = true;
            var output: []const u8 = "main.rrs";
            var aes_key = try aes.generateKeyBase64(allocator);
            while (i < args.len) : (i += 1) {
                if (eq(args[i], "-q") or eq(args[i], "--quiet")) {
                    noquiet = false;
                } else if (eq(args[i], "-o") or eq(args[i], "--output")) {
                    if (i + 1 >= args.len) @panic("The -o parameter must be follow by another arguments!");
                    const op_ext = std.fs.path.extension(args[i + 1]);
                    if (eq(op_ext, ".rrs")) {
                        output = args[i + 1];
                    } else {
                        output = try std.fmt.allocPrint(allocator, "{s}.rrs", .{args[i + 1]});
                    }
                    i += 1;
                } else if (eq(args[i], "-k") or eq(args[i], "--key")) {
                    if (i + 1 >= args.len) @panic("The -k parameter must be follow by another arguments!");
                    aes_key = args[i + 1];
                    i += 1;
                }
            }
            // print("LuaPath: {s}\nIsQuiet: {}\nOutputFile: {s}\nAES_Key: {s}\n", .{ lua_path, !noquiet, output, aes_key });
            if (noquiet) print("正在提取 main.lua 文件...\n", .{});
            const lua_file = try getFile(lua_path);
            if (noquiet) print("已读取到 main.lua 文件，正在分析依赖...\n", .{});
            const lua_par = try luaParser(lua_file, allocator);
            if (noquiet) print("依赖分析完毕，正在分析 AES_KEY...\n", .{});
            const real_key = aes.base64DecodeFixed(aes_key) catch {
                @panic("AES_KEY 解析失败！请检查你输入的 AES_KEY 是否正确。");
            };
            if (noquiet) print("密钥分析完毕！开始打包 {} 个文件...\n", .{lua_par.len + 1});
            const raw_data = try aes.packFiles(allocator, lua_par);
            defer allocator.free(raw_data);
            if (noquiet) print("打包完毕，正在填充剩余存储使得其字节数达到 16 的倍数...\n", .{});
            const padded_data = try aes.pkcs7Pad(allocator, raw_data);

            if (noquiet) print("填充完毕，正在生成随机偏移...\n", .{});
            var iv: [16]u8 = undefined;
            std.crypto.random.bytes(&iv);

            if (noquiet) print("偏移生成完毕，正在加密数据...\n", .{});
            const encrypted = try aes.aes256CbcEncrypt(allocator, padded_data, real_key, iv);
            defer allocator.free(encrypted);

            if (noquiet) print("加密数据完毕，正在写出到文件 {s}...\n", .{output});
            // 自主实现一个写出偏移+数据的函数
            const out_file = try std.fs.cwd().createFile(output, .{});
            defer out_file.close();
            try out_file.writeAll(&iv);
            try out_file.writeAll(encrypted);
            if (noquiet) print("写出文件 {s} 完毕，总共生成了：{} 字节！\n", .{ output, 16 + encrypted.len });
            print("你的 AES 密钥是：{s}\n请妥善保管好你的密钥。不要随意上传或者忘记了！！建议保存到本地！\n", .{aes_key});
        }
    }
}
