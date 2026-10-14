# AniCh 离线版

基于 AniCh 1.0.0，新增可实际使用的离线缓存。Android 包名 `io.github.upwon.anich.offline`，应用名「AniCh 离线版」，与原版同时安装，数据分别保存。

## 下载与使用

从 [本仓库 Releases](https://github.com/upwon/AniCh/releases/latest) 下载 APK。现代 Android 手机选择 `AniCh-Offline-arm64.apk`。

1. 打开番剧播放页，点击「缓存」。
2. 选择线路与剧集，可全选或多选，点击「开始缓存」。
3. 首页「缓存」或个人中心「离线缓存」查看进度、暂停、继续、重试或删除。
4. 在「已缓存」点击剧集，即可断网播放，支持记忆播放进度与播放器原生控制。

支持直接视频文件和 M3U8 点播播放列表（主列表画质选择、相对地址、AES-128 密钥、初始化片段、字节范围）。独立外置音轨、DRM 与直播会提示换线路。地址过期时，未冻结列表的任务会重新解析原线路。

**当前边界：** 下载时请保持应用运行；暂未加入 Android 前台下载服务，系统杀进程后可重新打开手动续传。MP4 仅在服务器提供 ETag／Last-Modified 且正确支持 Range 时从断点续传，否则安全地重新下载；M3U8 保留已完成分片。离线播放不加载在线弹幕。真实线路能否下载取决于服务端返回，不能保证所有线路都支持。

## GitHub 构建与签名

工作流 `.github/workflows/android.yml` 使用 Flutter 3.24.5 与 JDK 17，运行离线下载测试后构建三个 ABI 的 Release APK。main 提交会产出 Actions artifact；推送 `v*` 标签会自动发布 Release。

沿用搜索直达与 ytdlnis-pro 的 GitHub Secrets 配置方式，**为此应用使用单独固定签名**：

- `BASE_64_SIGNING_KEY`：JKS 文件的 Base64。
- `LOCAL_PROPERTIES`：`storePassword`、`keyPassword`、`keyAlias`、`storeFile` 四项，`storeFile=release_keystore.jks`。

签名文件仅在构建时注入，密钥和密码不得提交到仓库。每次发布都使用同一套 Secrets，之后可覆盖升级；工作流会输出 APK 证书信息与 SHA256 校验值。缺少签名时 Release 构建会失败，不会悄悄换成随机 debug 签名。

## 验证

`flutter test test/offline_download_test.dart` 测试本地 HTTP 服务上的文件下载、M3U8 本地化、暂停续传、重启恢复、失败任务与删除。测试不依赖第三方番剧源。

---

<h1 align="center">AniCh</h1>

<p align="center">一个支持超分辨率的在线动漫弹幕APP。多平台，多番剧源，多弹幕，高清无广告。追番看番必备软件。</p>

<div align="center">

[![GitHub release](https://img.shields.io/github/v/release/Sle2p/AniCh)](https://github.com/Sle2p/AniCh/releases/latest)
[![Stars](https://img.shields.io/github/stars/Sle2p/AniCh)](https://github.com/Sle2p/AniCh/stargazers)
[![GitHub all releases](https://img.shields.io/github/downloads/Sle2p/AniCh/total)](https://github.com/Sle2p/AniCh/releases/latest)

</div>

## 下载

点击前往 [发布页](https://github.com/Sle2p/AniCh/releases/latest) 下载

## 预览
开发中。实际样式请以最新版本为准。

| ![1](./screenshots/1.jpg) | ![2](./screenshots/2.jpg) |
| ---- | ---- |

| ![3](./screenshots/3.jpg) | ![4](./screenshots/4.jpg) |
| ---- | ---- |

## 功能

- [x] 超分辨率
- [x] 番剧索引
- [x] 番剧搜索
- [x] 倍速播放
- [x] 观看记录
- [x] 追番管理
- [x] 番剧弹幕
- [x] 弹幕举报
- [x] 弹幕过滤
- [x] 分集评论
- [x] 离线缓存
- [ ] 番剧评分
- [ ] ...

## 说明

> [!IMPORTANT]
> 源码对应版本 [1.0.0](https://github.com/Sle2p/AniCh/releases/tag/1.0.0)
>
> 日期：2024-08-25