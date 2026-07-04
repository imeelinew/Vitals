import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var cpuCheck: NSButton!
    private var memCheck: NSButton!
    private var pressureCheck: NSButton!
    private var launchCheck: NSButton!
    private var tabButtons: [NSButton] = []
    private var contentViews: [NSView] = []
    private var exclusionScrollView: NSScrollView!
    private var exclusionContainer: NSStackView!

    private let winWidth: CGFloat = 440
    private let winHeight: CGFloat = 460
    private let margin: CGFloat = 20
    private let tabHeight: CGFloat = 28
    private let tabSpacing: CGFloat = 4

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vitals 设置"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: winWidth, height: winHeight)
        window.contentMaxSize = NSSize(width: winWidth, height: winHeight)
        super.init(window: window)
        window.delegate = self
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }
        let contentW = winWidth - margin * 2

        let tabNames = ["菜单栏", "通用"]
        let tabW: CGFloat = 90
        for (i, name) in tabNames.enumerated() {
            let btn = NSButton(frame: NSRect(
                x: margin + CGFloat(i) * (tabW + tabSpacing),
                y: winHeight - margin - tabHeight,
                width: tabW,
                height: tabHeight
            ))
            btn.title = name
            btn.bezelStyle = .recessed
            btn.controlSize = .large
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.tag = i
            contentView.addSubview(btn)
            tabButtons.append(btn)
        }

        let contentY = margin
        let contentH = winHeight - margin * 2 - tabHeight - 8
        let contentRect = NSRect(x: margin, y: contentY, width: contentW, height: contentH)

        let menubarView = buildMenubarTab(frame: contentRect)
        let generalView = buildGeneralTab(frame: contentRect)
        contentView.addSubview(menubarView)
        contentView.addSubview(generalView)
        contentViews = [menubarView, generalView]

        selectTab(0)
    }

    private func buildMenubarTab(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.cornerRadius = 6

        let box = NSBox(frame: view.bounds)
        box.boxType = .custom
        box.isTransparent = false
        box.borderColor = .separatorColor
        box.contentViewMargins = .zero
        view.addSubview(box)

        let title = NSTextField(labelWithString: "菜单栏显示项")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.sizeToFit()
        title.frame.origin = NSPoint(x: 16, y: frame.height - 32)
        view.addSubview(title)

        let items = DisplayItem.allCases
        for (i, item) in items.enumerated() {
            let cb = NSButton(checkboxWithTitle: item.label, target: self, action: #selector(displayToggled(_:)))
            cb.font = .systemFont(ofSize: 13)
            cb.sizeToFit()
            cb.frame = NSRect(x: 16, y: frame.height - 64 - CGFloat(i) * 26, width: frame.width - 32, height: 22)
            switch item {
            case .cpu: cpuCheck = cb
            case .memory: memCheck = cb
            case .pressure: pressureCheck = cb
            }
            view.addSubview(cb)
        }

        let hint = NSTextField(labelWithString: "至少保留一项显示")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: 16, y: frame.height - 64 - CGFloat(items.count) * 26 - 8)
        view.addSubview(hint)

        return view
    }

    private func buildGeneralTab(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.cornerRadius = 6

        let box = NSBox(frame: view.bounds)
        box.boxType = .custom
        box.isTransparent = false
        box.borderColor = .separatorColor
        box.contentViewMargins = .zero
        view.addSubview(box)

        var y = frame.height - 32

        let launchTitle = NSTextField(labelWithString: "开机启动")
        launchTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        launchTitle.sizeToFit()
        launchTitle.frame.origin = NSPoint(x: 16, y: y)
        view.addSubview(launchTitle)
        y -= 28

        launchCheck = NSButton(checkboxWithTitle: "登录时自动启动 Vitals", target: self, action: #selector(launchToggled))
        launchCheck.font = .systemFont(ofSize: 13)
        launchCheck.sizeToFit()
        launchCheck.frame = NSRect(x: 16, y: y, width: frame.width - 32, height: 22)
        view.addSubview(launchCheck)
        y -= 36

        let excludeTitle = NSTextField(labelWithString: "排除应用")
        excludeTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        excludeTitle.sizeToFit()
        excludeTitle.frame.origin = NSPoint(x: 16, y: y)
        view.addSubview(excludeTitle)
        y -= 20

        let excludeHint = NSTextField(labelWithString: "勾选的应用不会出现在菜单栏的应用列表中")
        excludeHint.font = .systemFont(ofSize: 11)
        excludeHint.textColor = .secondaryLabelColor
        excludeHint.sizeToFit()
        excludeHint.frame.origin = NSPoint(x: 16, y: y)
        view.addSubview(excludeHint)
        y -= 12

        let scrollH = y - 16
        exclusionScrollView = NSScrollView(frame: NSRect(x: 16, y: 16, width: frame.width - 32, height: scrollH))
        exclusionScrollView.hasVerticalScroller = true
        exclusionScrollView.autohidesScrollers = false
        exclusionScrollView.borderType = .bezelBorder
        exclusionScrollView.drawsBackground = true
        exclusionScrollView.backgroundColor = .windowBackgroundColor

        let clipW = exclusionScrollView.frame.width
        exclusionContainer = NSStackView(frame: NSRect(x: 0, y: 0, width: clipW, height: 0))
        exclusionContainer.orientation = .vertical
        exclusionContainer.alignment = .leading
        exclusionContainer.spacing = 4
        exclusionContainer.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        exclusionScrollView.documentView = exclusionContainer
        view.addSubview(exclusionScrollView)

        return view
    }

    @objc private func tabClicked(_ sender: NSButton) {
        selectTab(sender.tag)
    }

    private func selectTab(_ index: Int) {
        for (i, btn) in tabButtons.enumerated() {
            btn.state = (i == index) ? .on : .off
            btn.font = i == index
                ? .systemFont(ofSize: 13, weight: .semibold)
                : .systemFont(ofSize: 13, weight: .regular)
        }
        for (i, view) in contentViews.enumerated() {
            view.isHidden = (i != index)
        }
        if index == 1 {
            rebuildExclusionList()
        }
    }

    private func syncControls() {
        cpuCheck.state = AppSettings.shared.isEnabled(.cpu) ? .on : .off
        memCheck.state = AppSettings.shared.isEnabled(.memory) ? .on : .off
        pressureCheck.state = AppSettings.shared.isEnabled(.pressure) ? .on : .off
        launchCheck.state = LaunchAtLogin.isEnabled ? .on : .off
        if !contentViews[1].isHidden {
            rebuildExclusionList()
        }
    }

    private func rebuildExclusionList() {
        exclusionContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let apps = AppListSection.collectAll()
        let rowW = exclusionScrollView.frame.width - 20

        for info in apps {
            let name = info.displayName
            let bid = info.app.bundleIdentifier ?? ""
            let cb = NSButton(checkboxWithTitle: name, target: self, action: #selector(exclusionToggled(_:)))
            cb.font = .systemFont(ofSize: 12)
            cb.state = AppSettings.shared.isExcluded(bid) ? .on : .off
            cb.identifier = NSUserInterfaceItemIdentifier(rawValue: bid)
            cb.sizeToFit()
            cb.frame.size.width = rowW
            exclusionContainer.addArrangedSubview(cb)
        }
        if apps.isEmpty {
            let empty = NSTextField(labelWithString: "（当前没有运行中的应用）")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 12)
            empty.sizeToFit()
            empty.frame.size.width = rowW
            exclusionContainer.addArrangedSubview(empty)
        }
    }

    @objc private func displayToggled(_ sender: NSButton) {
        let item: DisplayItem
        if sender === cpuCheck { item = .cpu }
        else if sender === memCheck { item = .memory }
        else { item = .pressure }
        AppSettings.shared.setEnabled(item, sender.state == .on)
        syncControls()
    }

    @objc private func launchToggled() {
        let enable = launchCheck.state == .on
        do {
            if enable { try LaunchAtLogin.enable() }
            else { try LaunchAtLogin.disable() }
        } catch {
            print("[launch] error: \(error)")
        }
        launchCheck.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func exclusionToggled(_ sender: NSButton) {
        guard let bid = sender.identifier?.rawValue else { return }
        AppSettings.shared.setExcluded(bid, sender.state == .on)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        syncControls()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }
}
