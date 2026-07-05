import AppKit

final class StatusPanelView: NSView {
    private weak var collector: MetricsCollector?
    private let cpuLabel = NSTextField(labelWithString: "")
    private let cpuBar = BarView()
    private let memLabel = NSTextField(labelWithString: "")
    private let memBar = BarView()
    private let pressureLabel = NSTextField(labelWithString: "内存压力")
    private let pressureDot = DotView()

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let titleFont = NSFont.systemFont(ofSize: 12, weight: .regular)

    override var isFlipped: Bool { true }

    init(collector: MetricsCollector) {
        self.collector = collector
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        setup()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        let contentWidth: CGFloat = 196
        let x: CGFloat = 12
        var y: CGFloat = 10

        cpuLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 14)
        addSubview(cpuLabel)
        y += 18

        cpuBar.frame = NSRect(x: x, y: y, width: contentWidth, height: 8)
        addSubview(cpuBar)
        y += 18

        memLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 14)
        addSubview(memLabel)
        y += 18

        memBar.frame = NSRect(x: x, y: y, width: contentWidth, height: 8)
        addSubview(memBar)
        y += 18

        pressureLabel.font = titleFont
        pressureLabel.frame = NSRect(x: x, y: y, width: 80, height: 14)
        addSubview(pressureLabel)

        pressureDot.frame = NSRect(x: x + contentWidth - 14, y: y + 1, width: 12, height: 12)
        addSubview(pressureDot)
    }

    func refresh() {
        guard let c = collector else { return }
        let cpuText = c.hasCPUSample ? "\(Int(c.cpuUsage.rounded()))%" : "--"
        let memText = "\(Int(c.memoryUsage.rounded()))%"

        cpuLabel.attributedStringValue = rowAttr("CPU", value: cpuText)
        memLabel.attributedStringValue = rowAttr("内存", value: memText)

        cpuBar.value = c.cpuUsage
        memBar.value = c.memoryUsage
        pressureDot.color = c.pressure.color
    }

    private func rowAttr(_ title: String, value: String) -> NSAttributedString {
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: title + "  ", attributes: [
            .font: titleFont, .foregroundColor: NSColor.labelColor
        ]))
        attr.append(NSAttributedString(string: value, attributes: [
            .font: monoFont, .foregroundColor: NSColor.labelColor
        ]))
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        return attr
    }
}
