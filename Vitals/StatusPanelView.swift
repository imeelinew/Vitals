import AppKit

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let cpuValue = NSTextField(labelWithString: "--")
    private let cpuProgress = NSProgressIndicator()
    private let memValue = NSTextField(labelWithString: "--")
    private let memProgress = NSProgressIndicator()
    private let dot = NSView()
    private let pressureLabel = NSTextField(labelWithString: "内存压力：正常")
    private let bytesLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(collector: MetricsCollector) {
        self.collector = collector
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 140))
        setup()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        let contentWidth: CGFloat = 196
        let x: CGFloat = 12
        var y: CGFloat = 10

        let cpuTitle = NSTextField(labelWithString: "CPU")
        cpuTitle.frame = NSRect(x: x, y: y, width: 40, height: 14)
        addSubview(cpuTitle)
        cpuValue.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cpuValue.alignment = .right
        cpuValue.frame = NSRect(x: x + contentWidth - 50, y: y, width: 50, height: 14)
        addSubview(cpuValue)
        y += 18

        configureProgress(cpuProgress)
        cpuProgress.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        addSubview(cpuProgress)
        y += 20

        let memTitle = NSTextField(labelWithString: "内存")
        memTitle.frame = NSRect(x: x, y: y, width: 40, height: 14)
        addSubview(memTitle)
        memValue.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        memValue.alignment = .right
        memValue.frame = NSRect(x: x + contentWidth - 50, y: y, width: 50, height: 14)
        addSubview(memValue)
        y += 18

        configureProgress(memProgress)
        memProgress.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        addSubview(memProgress)
        y += 22

        dot.wantsLayer = true
        dot.frame = NSRect(x: x, y: y + 2, width: 10, height: 10)
        addSubview(dot)
        pressureLabel.frame = NSRect(x: x + 18, y: y, width: contentWidth - 18, height: 14)
        addSubview(pressureLabel)
        y += 22

        bytesLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        bytesLabel.textColor = .secondaryLabelColor
        bytesLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        addSubview(bytesLabel)
    }

    private func configureProgress(_ p: NSProgressIndicator) {
        p.minValue = 0
        p.maxValue = 100
        p.isIndeterminate = false
        p.style = .bar
        p.controlSize = .small
    }

    func refresh() {
        guard let c = collector else { return }
        cpuValue.stringValue = c.hasCPUSample ? "\(Int(c.cpuUsage.rounded()))%" : "--"
        cpuProgress.doubleValue = max(0, c.cpuUsage)
        memValue.stringValue = "\(Int(c.memoryUsage.rounded()))%"
        memProgress.doubleValue = c.memoryUsage
        pressureLabel.stringValue = "内存压力：\(c.pressure.label)"
        if dot.layer == nil {
            dot.layer = CALayer()
            dot.layer?.cornerRadius = 5
        }
        dot.layer?.backgroundColor = pressureColor.cgColor
        bytesLabel.stringValue = "\(formatBytes(c.memoryUsedBytes)) / \(formatBytes(c.totalMemoryBytes))"
    }

    private var pressureColor: NSColor {
        switch collector?.pressure {
        case .warning: return .systemYellow
        case .critical: return .systemRed
        default: return .systemGreen
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
