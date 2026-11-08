# DSH 更新日志

## 1.0.1（2026-11-08）

- 「打开」改回全屏 WKWebView（无地址栏），并在页面脚本运行前注入 JS 垫片：
  `AbortSignal.any`、`AbortSignal.timeout`、`Promise.withResolvers`、`Object.groupBy`。
  这些 API 在 iOS 17.4 之前不存在，dsh 前端调用它们会抛
  `AbortSignal.any is not a function`（例如「选择工作区目录」），垫片让 iOS 16、
  17.0–17.3 也能正常用。
- 启动 / 停止移到包内的隐藏辅助 app `DSH 助手`（bundle id
  `bc.8848.dshcontrol.helper`）：主应用因 WebKit 需要数据容器而被沙盒约束，无法
  `exec` / `kill`；辅助 app 以免沙盒签名，由 `dshhelper://start|stop` 唤起，
  完成后把结果写到 `/tmp/dsh-helper.json` 并回到主应用。
- 主应用改为「有数据容器」的沙盒 app，用 entitlements 的文件例外访问
  `/var/mobile/Documents/dsh/` 与 `/private/var/tmp/`。

### 已知限制

- 点「启动 / 停止」时屏幕会短暂切到辅助 app 再切回（约 0.5–1 秒）。
- 辅助 app 用 `SBAppTags=hidden` 声明为隐藏应用，是否真的不出现在桌面未在本机确认。

## 1.0.0（2026-11-08）

首个版本：本机 DeepSeek Harness（dsh）控制面板。

- 开机自启开关：切换时创建或删除 `/var/mobile/Documents/dsh/autostart.off`，
  与 daemon 读取的是同一个文件。
- 服务状态：对 127.0.0.1:3080 做一次 TCP 探测，显示「运行中 / 未运行」和 PID，
  前台时每 2 秒自动刷新。
- 打开 DeepSeek Harness：从 `/tmp/dsh-web.log` 取最新的 token 链接并全屏打开；
  日志里没有链接时提示先启动。
- 启动 / 停止：启动执行 `/var/mobile/Documents/dsh/dsh`（经 bootstrap 的
  `/bin/sh` 执行，因为 iOS 自身没有 shebang 指向的 `/bin/sh`）；停止读取
  `dsh-web.pid`、发送 SIGTERM，卡住时升级为 SIGKILL，并在确认端口关闭后清理
  过期 pid 文件。
- 诊断日志：`/tmp/dsh-control.log`，同时以 os_log 输出（subsystem
  `bc.8848.dshcontrol`）。
