# 在 dsh 里写一个越狱插件的流程

本环境没有 Apelin 的 `apelin_*` 工具，但编译、签名、打包都能用 shell 完成。
用户说"给我写个插件，功能是……"时，按下面这条流水线走，不要反问能查到的东西。

## 0. 先确认三件事（只问这三件）

1. **功能边界**：挂在哪个 app / 哪个界面、什么条件下、要什么效果。含糊就问一句，
   不要自己编大范围的东西。
2. **标识符与作者**：包名默认 `bc.8848.<英文名小写>`，作者默认 `8848`。用户另有
   要求就照办。
3. **装不装**：按用户习惯先问"以后默认装，还是默认不装"。默认装就在打包后提示
   可以装；默认不装就把 `.deb` 路径发出来。

## 1. 建目录

```
<工作目录>/
  Sources/Tweak.m        # 一个或多个 .m
  build/                 # 产物（.gitignore 掉）
```

不要用 Theos：没有 Logos 预处理器，不要写 `%hook`、`.x`、`.xm`、`Makefile`。
挂钩子直接用 substrate C API：

```objc
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <substrate.h>

static os_log_t gLog;
static void (*originalFoo)(id, SEL);

static void hookedFoo(id self, SEL _cmd) {
    os_log(gLog, "MyTweak: foo");
    if (originalFoo) originalFoo(self, _cmd);
}

__attribute__((constructor)) static void MyTweakInit(void) {
    gLog = os_log_create("bc.8848.mytweak", "load");
    os_log(gLog, "MyTweak loaded");
    Class cls = objc_getClass("SomeClass");
    SEL sel = @selector(foo);
    if (cls && class_getInstanceMethod(cls, sel)) {
        MSHookMessageEx(cls, sel, (IMP)hookedFoo, (IMP *)&originalFoo);
    }
}
```

## 2. 编译 + 打包

```sh
NAME=MyTweak PKG=bc.8848.mytweak FILTER=com.apple.springboard \
  SRC=Sources OUT=build /var/mobile/.dsh/bin/ios-tweak-build.sh
```

一条命令出 `<OUT>/bc.8848.mytweak_1.0.0_iphoneos-arm64.deb`（rootless、arm64+arm64e、
已 ldid 签名）。`FILTER` 是要注入的 bundle id，多个用逗号分隔；SpringBoard 是
`com.apple.springboard`。

编译报错就按 `文件:行` 改源码再跑，不要改脚本去绕过选项。

## 3. 代码规矩（写之前就想清楚，别写完再返工）

- **只挂钩最小的方法**，除非用户要求替换，否则一定调原实现。
- **永远不要阻塞主线程**（SpringBoard 里会变成无限重启）。
- 钩子函数、保存的原实现、全局变量都要 `static`；类名和方法名加自己的前缀，
  同一进程里还装着别人的几十个插件。
- 用 `MSHookMessageEx`/`MSHookFunction`，不要 `method_exchangeImplementations`
  或 `method_setImplementation`（会顶掉别人的钩子）。
- 只链接 SDK 里的公开框架；私有类 `objc_getClass`，私有函数 `dlopen`+`dlsym`。
- `os_log` 的 subsystem 用包名，字符串要加 `%{public}` 才能在日志里看到。
- 拿不准类名或方法名时，用 `nm`/`llvm-otool` 看目标二进制，或让用户提供目标 app 的
  可执行文件路径；不要猜着写。

## 4. 交付

- 产物：`.deb` 的完整路径 + 一句话说明它做了什么。
- 版本简单地从 `1.0.0` 开始；每改一版给中文更新日志（写进交付说明即可）。
- **装不了**：本环境以 mobile 运行，没有 dpkg 权限。明确告诉用户"把包放进
  文件 app，用 Sileo/Zebra/Irisin 安装"，或让其交回 Apelin 那边安装。
- 装上后注入 SpringBoard 需要 respring 才生效；这一步也让用户做。

## 5. 用户报"没效果"时

先要日志：`os_log` 的行在设备的统一日志里，用户可以用 Console.app 或
`log stream --predicate 'subsystem == "bc.8848.mytweak"'` 看（需要越狱终端或
Apelin 会话）。拿不到日志时，按这个顺序自查：filter 的 bundle id 对不对、
方法名/类名在目标系统上是否真存在、构造函数是否执行（有没有 "loaded" 那行）。
