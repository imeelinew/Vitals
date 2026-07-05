import AppKit

final class DotView: NSView {
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let inset: CGFloat = 2
        let d = min(bounds.width, bounds.height) - inset * 2
        let r = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        NSBezierPath(ovalIn: r).fill()
    }
}

final class BarView: NSView {
    var value: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
        let pct = min(max(value, 0), 100) / 100
        let w = r.width * CGFloat(pct)
        if w > 0 {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: r.height),
                         xRadius: 2, yRadius: 2).fill()
        }
    }
}
