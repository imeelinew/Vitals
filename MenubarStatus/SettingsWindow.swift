import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var cpuCheck: NSButton!
    private var memCheck: NSButton!
    private var pressureCheck: NSButton!
    private var launchCheck: NSButton!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MenubarStatus 设置"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])

        let displayTitle = NSTextField(labelWithString: "菜单栏显示")
        displayTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(displayTitle)

        let displayGroup = NSStackView()
        displayGroup.orientation = .vertical
        displayGroup.alignment = .leading
        displayGroup.spacing = 6

        cpuCheck = makeCheckbox(DisplayItem.cpu.label)
        memCheck = makeCheckbox(DisplayItem.memory.label)
        pressureCheck = makeCheckbox(DisplayItem.pressure.label)
        displayGroup.addArrangedSubview(cpuCheck)
        displayGroup.addArrangedSubview(memCheck)
        displayGroup.addArrangedSubview(pressureCheck)
        stack.addArrangedSubview(displayGroup)

        let generalTitle = NSTextField(labelWithString: "通用")
        generalTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(generalTitle)

        launchCheck = NSButton(checkboxWithTitle: "开机启动", target: self, action: #selector(launchToggled))
        stack.addArrangedSubview(launchCheck)

        syncControls()
    }

    private func makeCheckbox(_ title: String) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: #selector(displayToggled(_:)))
        return btn
    }

    private func syncControls() {
        cpuCheck.state = AppSettings.shared.isEnabled(.cpu) ? .on : .off
        memCheck.state = AppSettings.shared.isEnabled(.memory) ? .on : .off
        pressureCheck.state = AppSettings.shared.isEnabled(.pressure) ? .on : .off
        launchCheck.state = LaunchAtLogin.isEnabled ? .on : .off
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
