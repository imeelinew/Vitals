<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="Vitals">
</p>

<h1 align="center">Vitals</h1>

<p align="center">
  一个住在 macOS 菜单栏里的轻量系统监控。<br>
  CPU、内存、内存压力，以及一键清空工作区。
</p>


<p align="center">
  <a href="https://github.com/imeelinew/Vitals/releases">下载</a> ·
  <a href="#安装">安装</a> ·
  <a href="#从源码构建">从源码构建</a>
</p>

<p align="center">
  <a href="README.md">简体中文</a>
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/imeelinew/Vitals/releases/latest"><img src="https://img.shields.io/github/v/release/imeelinew/Vitals" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
</p>

---

<p align="center">
  <img alt="Vitals 菜单栏面板" src=".github/assets/app.png" width="360">
</p>

## 简介

Vitals 是一个常驻菜单栏的 macOS 系统监控工具，适合那些想随时看见 CPU、内存和内存压力，又希望快速关掉占内存应用、腾出工作区的人。

它刻意保持很轻：用原生 AppKit 自绘菜单界面，避免拉入 SwiftUI 一类重依赖，目标是把自身物理 footprint 压在很低的水平，好让监控工具本身不成为负担。

## 为什么开发 Vitals

活动监视器很完整，但对「看一眼资源、关掉几个占地方的 App」来说往往太重。Vitals 把最常用的几件事收进菜单栏：状态一眼可见，应用按内存排序，安全区里的应用不会被一键清掉。

- **菜单栏优先**：CPU、内存占用和内存压力直接显示在面板顶部。
- **按内存排序的应用列表**：带图标查看当前运行中的常规应用及其占用。
- **安全区**：把不想被批量退出的应用保护起来。
- **清空工作区**：一键退出未保护的应用，快速腾出内存和桌面。
- **轻量常驻**：为长时间挂在菜单栏而设计，采样与界面都按低 footprint 约束实现。

## 菜单栏

打开菜单即可看到 CPU、内存进度条和内存压力指示，以及当前运行中的应用列表。你可以勾选后退出选中应用，也可以直接清空工作区；安全区里的应用会单独列出，不会被批量操作误伤。

## 其他功能

- 可自定义菜单栏是否显示 CPU、内存、内存压力
- 开机自启
- 退出选中应用时关闭其全部窗口
- 应用图标与占用一并展示，方便快速识别
- 菜单关闭后销毁面板视图，避免常驻占内存

## 安装

从 [Releases 页面](https://github.com/imeelinew/Vitals/releases)下载最新版，解压后将 `Vitals.app` 拖入「应用程序」文件夹。需要 macOS 26 或更高版本。

## 从源码构建

```sh
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release build
```

构建产物在 Xcode DerivedData 的 `Build/Products/Release/Vitals.app`。Release 配置开启死代码剥离与 strip，便于验证 footprint。
