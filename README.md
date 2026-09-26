# Job Monitor for macOS

一个放在 Mac 桌面上的轻量职位提醒助手。

它用一个小型 **M 图标**常驻桌面。点击图标可以查看职位提醒、管理监控公司，并配置自己关注的岗位方向。界面尽量保持简单，不需要一直打开一个完整窗口。

> 当前版本是 `v0.1.0 Beta`。桌面组件、配置管理和提醒列表已经可以使用，但自动访问招聘网站的后台检索器还没有完全内置。请先阅读下面的“当前版本说明”。

## 它能做什么

- 在桌面显示一个可拖动、可折叠的 M 图标
- 添加和管理多家公司
- 保存公司名称与官方招聘网址
- 多选 Product、AI/ML 等岗位方向
- 支持实习岗位筛选配置
- 按提醒时间分组展示职位
- 每组职位提供“查看”按钮
- 查看后显示为“已查看”，但仍可再次打开
- 在图标上显示新消息红点
- 自动清理 14 天以前的提醒记录
- 所有配置和历史数据仅保存在本机

## 当前版本说明

这个 Beta 目前更像一套完整的桌面提醒界面，而不是已经完全独立的招聘爬虫。

目前仍需要外部调度器在完成岗位检索后，将结果写入 App 的提醒文件。开发者本机可以配合 Codex 定时任务使用，但其他用户仅下载这个版本后，**不会自动在每天 09:30 和 18:30 检索网站**。

后续版本计划加入：

- App 内置的官网职位检查器
- 每天 09:30、18:30 后台运行
- 登录时自动启动后台 Helper
- 网络失败重试与电脑唤醒后补查
- macOS 系统通知
- 更稳定的 LinkedIn 检索方式

## 下载安装

1. 打开项目的 [Releases 页面](https://github.com/mengyi11/job-monitor-macos/releases)。
2. 下载最新的 `JobMonitor-版本号.dmg`。
3. 打开 DMG，将 **Job Monitor** 拖入“应用程序”。
4. 第一次打开时，如果 macOS 提示无法验证开发者，请在 Finder 中右键 App，选择“打开”。
5. 找到桌面上的 M 图标，点击后进入监控公司和设置页面。

当前安装包采用临时签名，尚未经过 Apple Developer ID 签名和公证，因此首次启动体验与正式发行版会有差异。

## 配置监控公司

打开 M 图标后，进入“监控公司”或设置页面：

1. 粘贴公司的官方招聘网址。
2. App 会尝试根据网址识别公司名称，你也可以手动修改。
3. 选择一个或多个岗位方向。
4. 选择工作类型，目前主要面向 Internship / 实习岗位。
5. 点击“保存配置”。

配置只有在点击保存后才会出现在监控公司列表中。

## 数据保存在哪里

个人配置、提醒历史和岗位去重记录保存在：

```text
~/Library/Application Support/JobMonitor/
```

项目仓库和安装包不会包含开发者本人的：

- 公司监控配置
- LinkedIn Cookie 或登录信息
- 浏览历史
- 已查看岗位记录
- 个人职位提醒

## 关于 LinkedIn

LinkedIn 的搜索结果通常与登录状态、Cookie 和页面动态加载有关。App 不会直接复制或打包任何人的 Chrome 登录状态。

后续如果加入 LinkedIn 后台检查，需要使用者自行登录，或采用 LinkedIn 允许的公开数据/API 方案。公司官网通常会比 LinkedIn 更适合稳定监控。

## 给开发者

当前项目使用 Objective-C 和 Cocoa，可以通过 macOS Command Line Tools 编译：

```bash
xcrun clang -fobjc-arc -framework Cocoa work/MicronJobWidget.m \
  -o "Job Monitor.app/Contents/MacOS/MicronJobWidget"
```

主要源文件：

- `work/MicronJobWidget.m`：界面和本地数据逻辑
- `work/Info.plist`：macOS App 配置

## Roadmap

- [ ] 内置固定时间后台检查
- [ ] 登录时启动
- [ ] 系统通知
- [ ] 官网适配器和错误日志
- [ ] LinkedIn 登录与读取方案
- [ ] Apple Silicon / Intel Universal Build
- [ ] Developer ID 签名和 Apple 公证
- [ ] 自动更新

## License

MIT License
