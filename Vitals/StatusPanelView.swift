import AppKit

final class PressureBarView: NSView {
    var level: MemoryPressureState = .normal {
        didSet {
            if oldValue != level { needsDisplay = true }
        }
    }
    private let segmentCount = 3
    private let gap: CGFloat = 3
    private let cornerRadius: CGFloat = 2

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let totalGap = gap * CGFloat(segmentCount - 1)
        let segWidth = (bounds.width - totalGap) / CGFloat(segmentCount)
        let currentLevel: Int = level == .normal ? 1 : level == .warning ? 2 : 3

        for i in 0..<segmentCount {
            let x = bounds.minX + CGFloat(i) * (segWidth + gap)
            let rect = NSRect(x: x, y: bounds.minY, width: segWidth, height: bounds.height)
            let isActive = i < currentLevel
            (isActive ? activeColor : NSColor.underPageBackgroundColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }

    private var activeColor: NSColor {
        switch level {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }
}

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let cpuValue = NSTextField(labelWithString: "--")
    private let cpuProgress = NSProgressIndicator()
    private let memValue = NSTextField(labelWithString: "--")
    private let memProgress = NSProgressIndicator()
    private let pressureValue = NSTextField(labelWithString: "正常")
    private let pressureBar = PressureBarView()

    override var isFlipped: Bool { true }

    init(collector: MetricsCollector) {
        self.collector = collector
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 130))
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
        y += 20

        let pressureTitle = NSTextField(labelWithString: "内存压力")
        pressureTitle.frame = NSRect(x: x, y: y, width: 60, height: 14)
        addSubview(pressureTitle)
        pressureValue.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pressureValue.alignment = .right
        pressureValue.frame = NSRect(x: x + contentWidth - 50, y: y, width: 50, height: 14)
        addSubview(pressureValue)
        y += 18

        pressureBar.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        addSubview(pressureBar)
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
        pressureValue.stringValue = c.pressure.label
        pressureBar.level = c.pressure
    }
}
