# DSH 更新日志

## 1.0.0（2026-11-08）

首个版本：本机 DeepSeek Harness（dsh）控制面板。

- 开机自启开关：切换时创建或删除 `/var/mobile/Documents/dsh/autostart.off`，
  与 daemon 读取的是同一个文件。
- 服务状态：对 127.0.0.1:3080 做一次 TCP 探测，显示「运行中 / 未运行」和 PID，
  前台时每 2 秒自动刷新。
- 打开 DeepSeek Harness：从 `/tmp/dsh-web.log` 取最新的 token 链接并全屏打开；
  日志里没有链接时提示先启动。
- 启动 / 停止：启动执行 `/var/mobile/Documents/dsh/dsh`（异步，不阻塞界面，
  经 bootstrap 的 `/bin/sh` 执行，因为 iOS 自身没有 shebang 指向的 `/bin/sh`）；
  停止读取 `dsh-web.pid`、发送 SIGTERM，卡住时升级为 SIGKILL，并在确认端口关闭后
  清理过期 pid 文件。
- 诊断日志：`/tmp/dsh-control.log`，同时以 os_log 输出（subsystem
  `bc.8848.dshcontrol`），用于事后排查。

### 已知限制

本机 iOS 17.2.1 上，应用不启用沙盒（no-sandbox）时 WKWebView 不会启动渲染进程，
页面加载请求根本不会发出（`webView.URL` 始终为 nil）；而声明数据容器
（`container-required`）后 WebKit 正常，但容器会重新启用沙盒，`posix_spawn`
与 `kill` 均被拒绝（EPERM），启动/停止失效。二者在当前系统上互斥，本版本选择
保留启动/停止，打开页面改用 SFSafariViewController（功能完整，带 Safari 工具栏，
不是无地址栏的纯 WKWebView）。
