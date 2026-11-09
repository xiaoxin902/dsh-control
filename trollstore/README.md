# DSH Control · TrollStore（巨魔）版

这是同一套 App 的**独立发行版**：不装 deb、没有守护进程、不需要越狱。
用 `-DTROLLSTORE=1` 编译同一批源码，产出一个 `.tipa`，直接丢给 TrollStore 安装。

> **前提**：设备上必须已经有一份能跑的 dsh（Node 运行时 + `node_modules`）。
> TrollStore 设备没有 dpkg 和 `/var/jb`，所以运行时得你自己放——见下面「运行时」。
> 按我掌握的信息，TrollStore 覆盖的系统版本有限（大致 iOS 14.0–16.6.1 与 17.0 附近），
> 装之前先确认你的系统是否在支持范围内。

## 和越狱版的差别

| | 越狱版（deb） | 巨魔版（tipa） |
|---|---|---|
| 安装 | dpkg 装进 `/var/jb/Applications` | TrollStore 安装，进普通 App 容器 |
| 控制守护进程 | 有（start/stop/导出走请求文件） | **没有**，App 直接 `posix_spawn` / `kill` |
| 插件安装守护进程 | 有（root） | **没有**（这套功能不带） |
| 启动 dsh | 调 dsh 自己的启动脚本 | 同样调，但 node 路径可配置 |
| 停止 dsh | `kill(SIGTERM)`，失败再用 task port | 只用 `kill(SIGTERM)`（同 uid，够了） |
| 导出会话 | 由守护进程跑 node | App 自己跑 node（无沙箱，读得到 `~/.dsh`） |
| 开机自启 | 依赖 dsh 自己的 LaunchDaemon | **没有**；只做到「打开 App 时自动启动」 |

## 运行时（必须先解决）

TrollStore 设备上没有 dpkg，`nodejs22-ios-rootless` 装不进去。可选做法：

1. 把 Node 运行时手工解包到一个 App 读得到的位置，例如
   `/var/mobile/Documents/dsh-ts/bin/node22`（可执行），
   `node_modules` 按 dsh 的目录结构摆好；
2. 在配置文件里把路径写清楚（见下）。

App 不会去猜这些，找不到就报错并在 `/tmp/dsh-control.log` 记一行。

## 配置

可选文件 `/var/mobile/Documents/dsh-ts/config.json`，缺字段用默认值：

```json
{
  "dshDir":   "/var/mobile/Documents/dsh",
  "nodePath": "/var/mobile/Documents/dsh-ts/bin/node22",
  "path":     "/var/jb/usr/bin:/usr/bin:/bin",
  "tmpDir":   "/var/mobile/Documents/dsh/tmp"
}
```

- `nodePath`：不存在时会依次试 `/var/mobile/Documents/dsh-ts/bin/node22`、
  `/usr/local/bin/node22`，仍不行就按配置值报错。
- `path`：node 所在目录会自动排在它前面，所以 npm 之类也能找到。

## 构建

```sh
SDKROOT=/path/to/iPhoneOS.sdk ./trollstore/build-tipa.sh build
# → build/DSHControl.tipa
```

需要：clang（命令行工具链）、iPhoneOS SDK、`ldid`、`lipo`、`zip`。
SDK 不能随仓库分发，自己准备。

## 安装

1. TrollStore → 右上角 + → 选 `DSHControl.tipa`（**.tipa 而不是 .ipa**，TrollStore 会读包里的 entitlements）
2. 装完打开，先确认 `dshDir` / `nodePath` 配对了

## 已知限制 / 没验证的部分

- **没在真机上跑过**：手头这台是越狱设备，没有 TrollStore。
  已验证的只有：源码在 `-DTROLLSTORE=1` 下编译通过、arm64+arm64e 双架构、`ldid` 签名带上
  `platform-application` / `no-sandbox` / 路径例外、`.tipa` 结构正确。
- **开机自启没实现**：需要的话下一步是往 `~/Library/LaunchAgents` 注册用户 agent，
  但它能否跨重启被 launchd 重新加载，必须真机验证，我不敢先写死。
- **导出依赖 `~/.dsh`**：脚本读 `~/.dsh/sessions/*/session.v4.jsonl`，
  在 TrollStore 下靠 entitlements 里的 `/private/var/mobile/.dsh/` 只读例外；
  若你的 dsh 用的是别的 HOME，需要改脚本的符号链接或配置。
- 巨魔版**不带**插件安装守护进程（那套需要 root）。
