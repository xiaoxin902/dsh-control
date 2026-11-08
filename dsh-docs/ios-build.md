# 用 Apelin 的工具链和 SDK 在 dsh 里编译 iOS 插件

dsh 环境里**没有** `apelin_project_build` 这类工具，但 Apelin 安装到本机的编译器、
SDK 和注入头文件都在磁盘上，普通 shell 就能用。下面是在 dsh 里手搓 iOS 插件
（Objective-C dylib）的完整做法。本机是 **rootless**（Dopamine），路径以 `/var/jb`
开头；roothide 见文末。

## 有的东西

| 用途 | 路径 |
| --- | --- |
| 工具链（clang、ld、lipo、strip、dsymutil、nm、ar） | `/var/jb/usr/lib/apelin/toolchains/67525fd44741f8a0f7d7b2e7/usr/bin` |
| iPhoneOS SDK 17.2 | `/var/mobile/Documents/wiki.qaq.apelin/SDKs/iphoneos17.2-96db0f3e` |
| 注入 API 头文件 | `/var/jb/usr/share/apelin/development/wiki.qaq.apelin.dev.tweak/support/include/substrate.h` |
| 注入库链接桩 | `/var/jb/usr/share/apelin/development/wiki.qaq.apelin.dev.tweak/support/lib/rootless/libsubstrate.tbd` |
| 签名 | `ldid`（在 PATH 上） |
| 打包 | `dpkg-deb`、`tar`、`gzip`（在 PATH 上） |

链接桩里只有四个符号：`MSHookMessageEx`、`MSHookFunction`、`MSGetImageByName`、
`MSFindSymbol`。运行时的 `@rpath/CydiaSubstrate.framework/CydiaSubstrate` 由
mobilesubstrate 提供，所以包要 `Depends: mobilesubstrate`。

## 编译与链接的实际参数

```sh
CC=/var/jb/usr/lib/apelin/toolchains/67525fd44741f8a0f7d7b2e7/usr/bin/clang
SDK=/var/mobile/Documents/wiki.qaq.apelin/SDKs/iphoneos17.2-96db0f3e
DEV=/var/jb/usr/share/apelin/development/wiki.qaq.apelin.dev.tweak

# 每个架构分别编译（rootless 要 arm64 和 arm64e）
$CC -isysroot "$SDK" -arch arm64 -mios-version-min=16.0 \
    -O2 -fobjc-arc -fvisibility=hidden -Wall -Werror=unguarded-availability-new \
    -I"$DEV/support/include" -c Sources/Tweak.m -o Tweak.arm64.o

# 链接成 dylib，注入库走链接桩
$CC -isysroot "$SDK" -arch arm64 -mios-version-min=16.0 -dynamiclib \
    -L"$DEV/support/lib/rootless" -lsubstrate \
    -framework Foundation -framework UIKit \
    -install_name @rpath/MyTweak.dylib -o MyTweak.arm64.dylib Tweak.arm64.o

/var/jb/usr/lib/apelin/toolchains/*/usr/bin/lipo -create MyTweak.arm64.dylib MyTweak.arm64e.dylib -output MyTweak.dylib
/var/jb/usr/lib/apelin/toolchains/*/usr/bin/strip -x MyTweak.dylib
ldid -S MyTweak.dylib        # 每次重新链接后都要重签，否则进程加载时被杀
```

要点：
- 只用 SDK 里的**公开框架**。私有类用 `objc_getClass("X")` 拿，私有函数用
  `dlopen`+`dlsym`，不要 `-undefined dynamic_lookup`（arm64e 上会绑出没有指针
  认证的切片，第一次用常量字符串就崩）。
- `-fvisibility=hidden` 与 `-Werror=unguarded-availability-new` 是 Apelin 的规矩，
  保持它们能让代码在新旧系统上都安全。
- 模块名、类名、方法名都加自己的前缀：同一进程里还有别的插件。

## 打包

```
MyDeb/
  DEBIAN/control
  Library/MobileSubstrate/DynamicLibraries/MyTweak.dylib
  Library/MobileSubstrate/DynamicLibraries/MyTweak.plist   # 注入过滤
```

`control` 至少要有 `Package`、`Name`、`Version`、`Architecture`、`Description`、
`Author`、`Maintainer`、`Section`、`Depends: mobilesubstrate`；rootless 的
`Architecture` 是 `iphoneos-arm64`（roothide 是 `iphoneos-arm64e`）。

```sh
TMPDIR=/tmp dpkg-deb -b --root-owner-group MyDeb out.deb
```

**坑**：这个环境里的 `TMPDIR` 指向引导区的 `var/tmp`，mobile 不可写，
`dpkg-deb` 会报 `unable to create temporary directory`。打包时显式给一个可写目录
（同理，`mktemp` 也要给 `$HOME/.cache` 或 `/tmp`）。

## 现成脚本

`~/.dsh/bin/ios-tweak-build.sh`（同一份也在本项目 `tools/` 里）把上面全部串好了：

```sh
NAME=MyTweak PKG=bc.8848.mytweak FILTER=com.apple.springboard \
  SRC=Sources OUT=build /var/mobile/.dsh/bin/ios-tweak-build.sh
# => build/bc.8848.mytweak_1.0.0_iphoneos-arm64.deb
```

示例源码：`/var/mobile/.dsh/bin/example/Tweak.m`。

可选：`VER`（版本）、`AUTHOR`（默认 8848）、`FRAMEWORKS`（默认 `Foundation UIKit`）、
`BOOTSTRAP=roothide`。示例源码在 `tools/example/Sources/Tweak.m`。
本机实测：编译、lipo（arm64+arm64e）、strip、ldid 签名、dpkg-deb 打包全部通过。

## 装到设备上

B 方案：这台设备上有一个 root 守护进程 `bc.8848.dshcontrol.installer`，它只做一件事——
把投进 inbox 的插件包装上。**dsh 自己仍然是 mobile，没有 root**。

```sh
cp build/bc.8848.mytweak_1.0.0_iphoneos-arm64.deb /var/mobile/Documents/dsh/inbox/
sleep 20
cat /var/mobile/Documents/dsh/installer/result.json     # {"ok":true,"message":"installed"}
```

- 结果：`{"ok":true|false,"message":"…"}`；装过的包在 `installer/done/`，被拒的在
  `installer/rejected/`，全过程记录在 `installer/installer.log`。
- 它 5 秒轮询一次，通常 10–25 秒内有结果（Irisin 装包本身要十几秒）。
- **三道限制**：只处理 inbox 的 `*.deb`；带 `preinst/postinst/prerm/postrm` 的包直接
  拒绝；文件必须落在 `Library/MobileSubstrate/DynamicLibraries/`（rootless 的 deb 要
  带 `var/jb/` 前缀），出现别的路径或 setuid 文件同样拒绝。
- 因此自己的 `ios-tweak-build.sh` 产物可以直接投；**带脚本的包投进去只会被拒**。
- 卸载不归它管：删插件要用包管理器，或让 Apelin 那边的会话用 `apelin_package_remove`。
- 注入 SpringBoard 的插件装完需要 respring 才生效；dsh 没有 respring 工具，让用户做。


## roothide 的差别

`BOOTSTRAP=roothide` 时脚本只编 arm64e、`Architecture: iphoneos-arm64e`、链接桩换
`support/lib/roothide`、包路径不带 `/var/jb` 前缀。roothide 的引导根每次越狱都会
改名，**不要把解析出来的真实路径写进任何文件**，要写就写 `/var/jb`（rootless）或
相对/运行时解析。
