import AppKit

final class MetricBarView: NSView {
    var percent: Double = 0 {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    private let cornerRadius: CGFloat = 3

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let track = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.underPageBackgroundColor.setFill()
        track.fill()

        let clamped = max(0, min(100, percent))
        let fillWidth = bounds.width * CGFloat(clamped / 100.0)
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        fill.fill()
    }
}

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let cpuValue = NSTextField(labelWithString: "--")
    private let cpuProgress = MetricBarView()
    private let memValue = NSTextField(labelWithString: "--")
    private let memProgress = MetricBarView()
    private let pressureBar = MetricBarView()

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

        cpuProgress.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        cpuProgress.fillColor = .controlAccentColor
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

        memProgress.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        memProgress.fillColor = .controlAccentColor
        addSubview(memProgress)
        y += 20

        let pressureTitle = NSTextField(labelWithString: "内存压力")
        pressureTitle.frame = NSRect(x: x, y: y, width: 60, height: 14)
        addSubview(pressureTitle)
        y += 18

        pressureBar.frame = NSRect(x: x, y: y, width: contentWidth, height: 12)
        addSubview(pressureBar)
    }

    func refresh() {
        guard let c = collector else { return }
        cpuValue.stringValue = c.hasCPUSample ? "\(Int(c.cpuUsage.rounded()))%" : "--"
        cpuProgress.percent = max(0, c.cpuUsage)
        memValue.stringValue = "\(Int(c.memoryUsage.rounded()))%"
        memProgress.percent = c.memoryUsage
        pressureBar.percent = c.pressurePercent
        pressureBar.fillColor = pressureColor(c.pressure)
    }

    private func pressureColor(_ state: MemoryPressureState) -> NSColor {
        switch state {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }
}
