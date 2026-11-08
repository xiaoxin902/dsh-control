# Apelin 工具知识文档（不是本环境的工具）

这里 13 篇文档描述的是 **Apelin** —— 这台 iPhone/iPad 上的另一个 IDE 助手 ——
的整套工具与工作流，从它自带的技能里导出。

> 重要：文档里出现的 `apelin_project_build`、`apelin_package_install`、
> `apelin_screen_read_tree`、`apelin_screen_interact`、`apelin_log_read`、
> `apelin_crash_list`、`apelin_package_confirm_loaded`、`apelin_device_respring`、
> `git_clone`、`irisin-cli` 等，**在本环境里都不存在**，你不能调用它们，也不要
> 假装调用或让用户等它们的结果。它们只是背景知识：用来理解用户提到的 Apelin
> 项目、包、插件、越狱环境，以及用别的工具（shell、编辑器、构建脚本）完成同类
> 工作时参照的做法与安全规则。

## 什么时候值得读

| 文档 | 用得上时 |
| --- | --- |
| `apelin-tweak-development.md` | 写/改 iOS 越狱插件（Objective-C dylib 注入），或把 Theos/Logos 项目改成普通 Objective-C |
| `apelin-bootstrap-paths.md` | 任何涉及 `/var/jb`、jbroot、`@PREFIX@`、`@ROOTFS@` 的路径问题（附件 `ApelinBootstrap.h`） |
| `apelin-tweak-runtime.md` | 插件在宿主进程里的日志、沙箱、读写设置、Darwin 通知 |
| `apelin-preference-bundle.md` | 给插件做设置面板（PreferenceLoader / PSListController） |
| `apelin-project-description.md` | 理解 Apelin 项目里的 `apelin-project.json` 构建描述 |
| `apelin-external-build.md` | 导入的仓库要按自己的脚本构建、打成一个 deb |
| `apelin-device-executables.md` | 自己编译并直接运行的程序需要 ldid 签名（附件 `Tool.entitlements`） |
| `apelin-packaging-and-install.md` | 打包、安装、标识符、maintainer 脚本、确认加载、卸载 |
| `apelin-package-dependencies.md` | 依赖包怎么装、为什么不用 apt/dpkg、Irisin 的排查命令 |
| `apelin-crash-triage.md` | 目标进程崩溃或重启循环时怎么读崩溃报告 |
| `apelin-icli.md` | `icli` 这个设备命令行工具能做什么（应用、屏幕、进程、launchd、包、probe） |
| `apelin-git-workflow.md` | 项目提交历史怎么维护、何时 push、何时才能强制推送 |
| `apelin-package-repository.md` | 维护 GitHub Pages 上的 APT 源（debs/、depictions、发布） |

## 与用户偏好的关系

用户对"作者 8848"、包标识符 `bc.8848.<xxx>`、补丁要能单独安装、装之前先问
默认策略这些要求，写在 `~/.dsh/AGENTS.md` 里，优先于这里的描述。这里的文档
只解释机制，不替你决定要不要动设备。
