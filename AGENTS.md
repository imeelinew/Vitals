# AGENTS.md

Vitals 是一个常驻菜单栏的 macOS 监控应用（LSUIElement），用户启动后 7×24 小时运行。**内存占用是最高优先级**，任何修改都必须保持物理 footprint 在低位（目标 ≤ 15 MB）。

## 硬性规则

1. **禁止引入会拉入 SwiftUI 的依赖。** 此前因 `ServiceManagement` 传递依赖 SwiftUI，footprint 一度飙到 72 MB。开机自启已改用 `~/Library/LaunchAgents/` plist 实现，不要切回 `SMAppService`。不要 `import SwiftUI`，不要 `import SwiftData`，不要用 AppIntents。

2. **禁止用 `NSImage(systemSymbolName:)`。** 它会加载整个 SFSymbols.framework（111 MB 映射 + per-process 状态）。用 `NSBezierPath` 自绘（见 `DotView.swift`）。

3. **菜单栏视图必须懒创建、菜单关闭即销毁。** `StatusPanelView` 和 `AppListView` 只能在 `menuNeedsUpdate` 创建、`menuDidClose` 置 nil。不要把它们存为常驻属性。

4. **不要持有重量级对象。** `RunningAppInfo` 只存 `pid` + 名字 + 字节数，不要存 `NSRunningApplication`。需要时用 `NSRunningApplication(processIdentifier:)` 临时获取。

5. **采样代码路径必须用 `autoreleasepool`。** `MetricsCollector.tick()`、`AppListSection.collectAll()` 这类每轮采样会创建大量临时对象的路径，都要包 `autoreleasepool` 防止 autorelease 积累。

6. **复用，不要新建。** `CPUMetrics` 用双缓冲 `swap(&previous, &current)`，不要每次 `sample()` 创建新数组。`renderTitle()` 复用同一个 `NSMutableAttributedString` 并用 `beginEditing/endEditing`。

7. **采样间隔不低于 5 秒。** 菜单栏数字不需要秒级刷新。更短的间隔只会制造更多垃圾。

## 构建配置

- `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS = NO`
- `DEAD_CODE_STRIPPING = YES`
- `STRIP_INSTALLED_PRODUCT = YES`（Release）

不要重新打开上述设置。

## 验证

改动内存相关代码后，用 Release 配置构建并用 `footprint <pid>` 确认物理 footprint 仍 ≤ 15 MB。用 `vmmap <pid> | grep -i swiftui` 确认 SwiftUI 未被加载。

## 背景

2026-07 的一次重构把 footprint 从 ~25 MB 推到 72 MB，根因是 `ServiceManagement` → SwiftUI 传递依赖 + SFSymbols + 视图常驻 + 2 秒采样。修复后降到 12 MB。本文件防止回退。
