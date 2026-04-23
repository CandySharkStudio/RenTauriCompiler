-- 声明角色（留空则默认为旁白。）
local George = Character("乔治", "#48ce41")
local Andrey = Character("安德烈", "#FF9900")
local Aside = Character("", "")
-- 声明图片资源（第一个参数填路径，第二个参数填 MIME 类型，具体 MIME 格式如下图显示！）
--[[
image/gif：GIF图片
image/webp：WebP图片
image/svg+xml：SVG矢量图
image/bmp：BMP位图
image/avif：AVIF图片
image/apng：APNG动图
audio/mpeg：MP3音频
audio/wav：WAV音频
audio/ogg：OGG音频
audio/aac：AAC音频
audio/flac：FLAC无损音频
audio/webm：WebM音频
video/mp4：MP4视频
video/mpeg：MPEG视频
video/ogg：OGG视频
video/webm：WebM视频
video/quicktime：MOV视频
video/x-msvideo：AVI视频
font/ttf：TrueType字体
font/otf：OpenType字体
font/woff：Web开放字体格式
font/woff2：WOFF 2.0
]]
-- 使用 Image 去声明一个图片文件，当然你也可以用 Base64Image 去声明一个 Base64 源码的图片（
-- 这里极其不建议使用 Base64，因为这样会导致体积变大。。
-- 所有背景图建议都搞成 16:9 的大小，例如 1920x1080 或者 2560x1440。
-- 角色立绘可以搞成竖着的，多大都可以。。因为 RenTauri 会手动帮各位调整！
local bg = Image("assets/image/Bg.png", "image/png")
-- Audio 函数用来初始化音乐！
local bgm = Audio("assets/audio/music.mp3", "audio/mpeg")
-- 音效建议使用 ogg，音乐建议使用 mp3，仅此而已。。
local snd = Audio("assets/audio/sound.ogg", "audio/ogg")
-- 下列定义了一个全局常量！DefaultInstance 第一个填变量名称，第二个填初始值！
-- DefaultInstance 只在当前存档有效，设置之后可以通过回退修改。
local book = DefaultInstance("book", false)
-- 你也可以定义一个所有存档通用的全局变量
-- DefaultGlobal 和 DefaultInstance 唯一的区别就是在它一旦被修改，就无法回退了！并且全存档通用！（哪怕换存档也没用）
local bool_global = DefaultGlobal("bool_global", false)
-- 文案代码程序一开始时执行的 Start 函数
function Start()
    -- 使用 Say 函数去显示对话！
    Say(George, "你好，我喜欢你！")
    Say(Andrey, "你怎么了？")
    -- 使用 Menu 作为选项，第一个值是全局唯一的 key！必须与上方的 DefaultInstance 的所有给区分开！
    -- 也就是说，第一个值不能与上方 DefaultInstance 的值重复！但是 DefaultGlobal 可以。。
    Menu("选项1", {
        -- 以键名做选项名，键值为一个函数。
        ["你为什么要去？"] = function()
            Say(George, "我不去你能怎么办？")
            -- 跳转到 Label2 这个函数（你只能使用 Jump！不能直接使用 Label2() 去跑！）
            Jump(Label2)
        end,
        ["我不去你养我？"] = function()
            Say(George, "我养你啊！")
            Jump(Label3)
        end
    })
    -- 由于两个选项均有 Jump，因此底下不会再有任何语句（即使有也不会执行了。）
end
-- 名称叫 Label2 的函数！
function Label2()
    Say(George, "你为什么要来这里？")
    Say(Andrey, "我就是要来这里！")
    Jump(Label4)
end
function Label3()
    Say(George, "好啊！你养我！")
    Say(Andrey, "那我可以来这里了吧！")
    Jump(Label4)
end
function Label4()
    Say(Aside, "于是他们过上了没羞没躁的生活~")
    --[[
    对应了 renpy 里面的：
    scene bg
    ]]
    -- 下面的 dissolve 也可以写 fade
    ShowScene(bg, "dissolve")
    --[[
    对应了 renpy 里面的：
    show bg at right
    with fade
    ]]
    ShowImage(bg, "fade", "right")
    -- 肯定还有 HideImage 的啦！
    -- 在 show 的时候，完全可以照着 renpy 去写的！完全不用纠结这是哪个的噢！
    HideImage(bg)
    -- 播放音乐（切记，在整个程序中最多只能有一首背景音乐播放！背景音乐默认循环！）
    -- 但是可以同时播放多个音效！因此如果你想营造多个不同背景音乐同时播放的话，你可以直接使用 PlaySound！
    -- 音乐可以设置渐入渐出属性，但是音效不能！下面两个参数分别是渐入和渐出（秒做单位）！
    PlayMusic(bgm, 1.0, 1.0)
    -- 每执行一个 PlayMusic 都会使得前一个直接播放结束！
    -- 暂停音乐！此时没有音乐播放了。。无需参数，上一个音乐会按照 fadeout 自动退出！
    StopMusic()
    -- 播放音效！音效可以同时播放很多个！
    PlaySound(snd)
    -- Pause 可以停顿几秒！也可以直接写 0 以触发鼠标再次点击才继续执行！
    Pause(0)
    Pause(3.0)
    Jump(Label5)
end

function Label5()
    -- 下面写 DefaultInstance 的事！
    Menu("选项2", {
        ["设置全局变量"] = function()
            -- 使用 SetValue 去修改任何一个变量！（无论是全局的还是局部的）
            SetValue(book_global, true)
        end,
        ["设置当前变量"] = function()
            SetValue(book, true)
        end
    })
    -- 下列使用 If 这个函数去判断上述的变量！
    -- 直接使用 GetValue 去判断即可！当然，上面由于是布尔值，因此这里可以直接不用写后面的 == true。。
    -- 但是为了让各位理解得好，我还是写吧！第一个值是 true 时执行的语句，第二个值是 false 时执行的语句！
    If(GetValue(book) == true, function()
        
    end, function()
    end)
    If()
    -- 直接写 return 以便于直接结束游戏！
    return
end