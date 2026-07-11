import AppKit

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let titleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let contentWidth: CGFloat = 196
    private let contentX: CGFloat = 12
    private lazy var titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.labelColor
    ]
    private lazy var valueAttributes: [NSAttributedString.Key: Any] = [
        .font: valueFont,
        .foregroundColor: NSColor.labelColor
    ]

    override var isFlipped: Bool { true }

    init(collector: MetricsCollector) {
        self.collector = collector
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let collector else { return }

        drawMetric(
            title: "CPU",
            value: collector.hasCPUSample ? "\(Int(collector.cpuUsage.rounded()))%" : "--",
            percentage: collector.cpuUsage,
            y: 10
        )
        drawMetric(
            title: "内存",
            value: "\(Int(collector.memoryUsage.rounded()))%",
            percentage: collector.memoryUsage,
            y: 46
        )

        let pressureY: CGFloat = 82
        ("内存压力" as NSString).draw(
            at: NSPoint(x: contentX, y: pressureY),
            withAttributes: titleAttributes
        )
        collector.pressure.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: contentX + contentWidth - 12, y: pressureY + 1, width: 8, height: 8)).fill()
    }

    private func drawMetric(title: String, value: String, percentage: Double, y: CGFloat) {
        (title as NSString).draw(
            at: NSPoint(x: contentX, y: y),
            withAttributes: titleAttributes
        )
        let valueSize = (value as NSString).size(withAttributes: valueAttributes)
        (value as NSString).draw(
            at: NSPoint(x: contentX + contentWidth - valueSize.width, y: y),
            withAttributes: valueAttributes
        )

        let barRect = NSRect(x: contentX, y: y + 18, width: contentWidth, height: 8)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

        let fraction = min(max(percentage, 0), 100) / 100
        let width = barRect.width * CGFloat(fraction)
        if width > 0 {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: barRect.minX, y: barRect.minY, width: width, height: barRect.height),
                xRadius: 2,
                yRadius: 2
            ).fill()
        }
    }
}
