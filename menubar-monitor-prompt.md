# macOS 菜单栏系统监控小工具 — 开发 Prompt

## 项目目标

用 Swift（SwiftUI + AppKit 混合架构，参考 `NSStatusItem` 常驻菜单栏模式）写一个**极简**的 macOS 菜单栏应用，只做三件事：

1. 显示 **CPU 平均占用率**（数值需与"活动监视器"完全一致）
2. 显示 **内存平均占用率**（数值需与"活动监视器"完全一致）
3. 显示 **内存压力**（绿 / 黄 / 红三态，逻辑和视觉都要和"活动监视器"一致）

这是我自用的工具，不上架 App Store，不需要沙盒（sandbox），不需要签名分发给别人。**唯一的核心诉求是极致轻量**：空闲状态下常驻内存占用应该在个位数到十几 MB 的量级，CPU 占用常年低于 1%。请把这一点当作最高优先级的设计约束，任何会显著增加体积或依赖的方案都不要用。

## 技术选型要求

- 纯 Swift，**不要用 Electron / React Native / 任何 Web 技术栈**。
- 界面用 `NSStatusItem` 挂在菜单栏，不要在 Dock 显示图标（`LSUIElement = true`，即 Info.plist 里加 `Application is agent (UIElement)`）。
- 点击菜单栏图标后弹出一个小面板（`NSPopover` 或简单的 SwiftUI View 均可），展示三个数值和内存压力色块。
- **不要引入任何第三方依赖库**（不需要 Alamofire、SwiftUICharts 之类的东西），系统自带的 `Darwin`、`Foundation`、`IOKit`、`Dispatch` 就足够。
- 项目结构尽量简单：一个 `AppDelegate`（管理 `NSStatusItem` 生命周期）+ 一个数据采集模块（负责调用底层 API）+ 一个 SwiftUI View（负责展示），不需要额外的架构分层。

## 三个指标的具体计算方式（关键部分，请严格照做）

macOS 没有公开、稳定的高层 API 直接吐出"活动监视器"上那三个数字，需要调用底层 Mach/BSD API 自己计算。以下是每个指标对应的正确实现方式：

### 1. CPU 平均占用率

用 `host_processor_info()` + `PROCESSOR_CPU_LOAD_INFO`，拿到每个核心的 `user / system / idle / nice` tick 计数。做法：

- 每隔固定采样间隔（建议 1-2 秒）读取一次所有核心的 tick 值；
- 用两次采样之间的**差值**（delta），而不是累计值，来计算占用率；
- 全核心占用率 = `(Σ user_delta + Σ system_delta) / (Σ user_delta + Σ system_delta + Σ idle_delta + Σ nice_delta) * 100`；
- 这个数值应该对应"活动监视器 → CPU 标签页"底部显示的 User % + System % 之和（即总占用率，不含 Idle）。

注意事项：
- 释放 `host_processor_info` 返回的内存（`vm_deallocate`），否则会有内存泄漏。
- 采样间隔不要太短（比如低于 0.5 秒），否则这个定时器本身就会成为耗电和 CPU 占用的来源，和我们轻量化的目标相悖。

### 2. 内存平均占用率

用 `host_statistics64()` + `HOST_VM_INFO64`，拿到 `vm_statistics64` 结构体，里面有这些字段：

- `free_count`（空闲页）
- `active_count`（活跃页）
- `inactive_count`（不活跃页）
- `wire_count`（Wired 内存）
- `compressor_page_count`（压缩内存）
- `internal_page_count`（App 私有内存页）
- `purgeable_count`（可丢弃/可清除页）
- `external_page_count`（文件缓存页，Cached Files）
- `speculative_count`（推测性预读页）

"活动监视器"里显示的"已用内存"**不是**简单的 `总内存 - free_count`，而是按下面的口径算的（这是让很多菜单栏监控工具数值对不上活动监视器的常见坑，务必按这个来）：

```
App Memory   = (internal_page_count - purgeable_count) * page_size
Wired Memory = wire_count * page_size
Compressed   = compressor_page_count * page_size

已用内存(Memory Used) = App Memory + Wired Memory + Compressed
```

`external_page_count`（文件缓存）**不计入**"已用内存"，这部分对应活动监视器里灰色的 "Cached Files"，是可以随时被回收的，不应该让用户误以为是"占用"。

内存占用率 = `已用内存 / 物理总内存 * 100`，物理总内存用 `host_page_size()` 拿到页大小，再乘以 `host_basic_info()` 里的 `max_mem` 或直接用 `sysctl hw.memsize`。

**请务必留一个自查步骤**：写完之后同时打开活动监视器和你的小工具，对比数值，如果长期存在明显偏差（超过几个百分点），大概率是 App Memory 的计算口径有细节出入，需要用活动监视器的 Memory 标签页反推校准，而不是猜一个数字就定死。

### 3. 内存压力（绿 / 黄 / 红）

这个不需要自己算百分比再分档，macOS 内核本身就直接提供了这个分类值，用它就是和活动监视器"完全一致"的正确做法：

- Sysctl 名称：`kern.memorystatus_vm_pressure_level`
- 返回值：`1` = 正常（绿），`2` = 警告（黄），`4` = 严重（红）
- 这三个数值和 Swift 的 `DispatchSource.MemoryPressureEvent`（`.normal` / `.warning` / `.critical`）是对应的

**强烈建议优先用事件驱动而不是轮询**：

```swift
let source = DispatchSource.makeMemoryPressureSource(
    eventMask: [.warning, .critical, .normal],
    queue: DispatchQueue.main
)
source.setEventHandler {
    let data = source.data // 得到 .warning / .critical，事件触发时更新 UI
}
source.resume()
```

这样只有在系统内存压力状态**发生变化**时才会触发回调，完全不需要定时器轮询，是这三个指标里最省资源的一个，务必用这种方式而不是每隔几秒 `sysctlbyname` 查一次。

（如果你想在启动时先拿到一次初始状态，可以用 `sysctlbyname("kern.memorystatus_vm_pressure_level", ...)` 读一次当前值做初始化，之后就完全交给 DispatchSource 驱动。）

## 性能预算（请在实现过程中反复对照）

- 空闲状态常驻内存：目标个位数到十几 MB，不接受超过 30MB。
- CPU 占用：长期应低于 1%，采样定时器不要设置得过于频繁。
- 不要引入任何后台网络请求、日志上报、崩溃统计 SDK 之类的东西——这些都是常见的"看似无关但偷偷吃内存"的来源。
- 内存压力用事件驱动（DispatchSource），CPU 和内存用量用低频轮询（1-2 秒一次已经足够肉眼实时），不需要做到每秒多次刷新。

## UI 要求（从简，不追求花哨）

- 菜单栏图标：纯文字即可，比如 `CPU 12% · MEM 68%`，不需要图标或图形化元素，尽量窄，不占地方。
- 点击后弹出的面板里：
  - CPU 占用率（数字 + 可选的简单进度条）
  - 内存占用率（数字 + 可选的简单进度条）
  - 内存压力：一个色块或圆点，绿 / 黄 / 红对应上面三个状态，配一行文字说明（"正常" / "警告" / "严重"）
- 不需要历史图表、不需要设置项、不需要开机启动配置界面——如果需要开机启动，直接在代码里用 `SMAppService` 注册，不用做 UI。

## 验收标准（写完之后怎么判断"对不对"）

1. 同时打开活动监视器和你的小工具，静置几分钟对比 CPU 和内存数值，误差应该在几个百分点以内，且趋势一致（活动监视器涨的时候你的也应该涨）。
2. 故意制造内存压力（比如打开很多个 Chrome 标签页，或者用 `stress` 类工具），观察活动监视器的内存压力图变黄/变红时，你的小工具是否也几乎同步变化。
3. 用活动监视器本身检查这个小工具自己的内存占用，确认在预算范围内（个位数到十几 MB）。
4. 让它跑一整天，确认内存占用不会像 Stats 那样随时间推移持续增长（这是很多同类工具的通病，务必检查有没有持有了不该持有的引用、定时器有没有正确释放）。

## 补充说明

如果最终发现某个数值反复对不上活动监视器，大概率是因为苹果没有完全公开这几个 API 的确切语义，社区里也是靠反复试验reverse engineering 出来的。遇到这种情况，优先信任"和活动监视器实测对比校准"的结果，而不是纠结于理论公式本身是否"标准"。
