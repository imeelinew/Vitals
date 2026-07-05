import AppKit

final class PressureProgressIndicator: NSProgressIndicator {
    var pressureState: MemoryPressureState = .normal {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillColor: NSColor
        switch pressureState {
        case .normal: fillColor = .systemGreen
        case .warning: fillColor = .systemYellow
        case .critical: fillColor = .systemRed
        }

        let bounds = self.bounds
        let radius: CGFloat = 3.5

        NSColor.underPageBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let clamped = max(0, min(100, doubleValue))
        let fillWidth = bounds.width * CGFloat(clamped / 100.0)
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let cpuValue = NSTextField(labelWithString: "--")
    private let cpuProgress = NSProgressIndicator()
    private let memValue = NSTextField(labelWithString: "--")
    private let memProgress = NSProgressIndicator()
    private let pressureBar = PressureProgressIndicator()

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
        y += 18

        configureProgress(pressureBar)
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
        pressureBar.doubleValue = c.pressurePercent
        pressureBar.pressureState = c.pressure
    }
}
