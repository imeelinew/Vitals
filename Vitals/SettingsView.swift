import SwiftUI

@available(macOS 26.0, *)
extension View {
    func settingsContentMargins() -> some View {
        self
            .contentMargins(.horizontal, 18, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
    }
}

@available(macOS 26.0, *)
struct SettingsView: View {
    @State private var settingsPage: SettingsPage = .menubar
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var runningApps: [RunningAppInfo] = []
    @State private var menuBarIconEnabled = AppSettings.shared.isMenuBarIconEnabled

    private let sidebarIconTheme: SidebarIconTheme = .professional
    private let sidebarIconStyle: SidebarIconStyle = .lucide
    private let sidebarIconTileSize = 22.0
    private let sidebarIconSymbolSize = 11.0
    private let sidebarIconCornerRadius = 6.0
    private let professionalSidebarIconSize = 15.0

    enum SettingsPage: String, CaseIterable, Hashable, Identifiable {
        case menubar
        case apps
        case general

        var id: String { rawValue }

        enum Group: String, CaseIterable, Identifiable {
            case content = "内容"

            var id: String { rawValue }
        }

        var group: Group { .content }

        var title: String {
            switch self {
            case .menubar: return "菜单栏"
            case .apps: return "应用"
            case .general: return "通用"
            }
        }

        var symbolName: String {
            switch self {
            case .menubar: return "gauge.with.needle"
            case .apps: return "square.grid.2x2.fill"
            case .general: return "gearshape.fill"
            }
        }

        var professionalIconResourceName: String {
            switch self {
            case .menubar: return "gauge"
            case .apps: return "layout-grid"
            case .general: return "settings"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            settingsDetail
        }
        .toolbar {
            ToolbarSpacer(.flexible)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background {
            WindowTransparencyConfigurator(enabled: true)
                .frame(width: 0, height: 0)
            WindowBackgroundBlur(materialAlpha: 1.0)
                .ignoresSafeArea()
        }
    }

    private var settingsSidebar: some View {
        AppKitSettingsSidebar(
            pages: SettingsPage.allCases,
            selectedPage: settingsPageBinding,
            badgeCount: { _ in nil },
            iconTheme: sidebarIconTheme,
            iconStyle: sidebarIconStyle,
            colorfulIconSize: sidebarIconTileSize,
            colorfulSymbolSize: sidebarIconSymbolSize,
            colorfulCornerRadius: sidebarIconCornerRadius,
            professionalIconSize: professionalSidebarIconSize
        )
        .navigationTitle("设置")
        .navigationSplitViewColumnWidth(min: 150, ideal: 180)
    }

    private var settingsPageBinding: Binding<SettingsPage?> {
        Binding(
            get: { settingsPage },
            set: { nextPage in
                guard let nextPage else { return }
                settingsPage = nextPage
            }
        )
    }

    @ViewBuilder
    private var settingsDetail: some View {
        NavigationStack {
            switch settingsPage {
            case .menubar:
                menubarPage
            case .apps:
                appsPage
            case .general:
                generalPage
            }
        }
        .navigationTitle(settingsPage.title)
    }

    private var menubarPage: some View {
        Form {
            Section {
                Toggle("菜单栏图标", isOn: menuBarIconBinding)

                if menuBarIconEnabled {
                    Toggle(DisplayItem.cpu.label, isOn: displayBinding(.cpu))
                    Toggle(DisplayItem.memory.label, isOn: displayBinding(.memory))
                    Toggle(DisplayItem.pressure.label, isOn: displayBinding(.pressure))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsContentMargins()
        .navigationTitle("菜单栏")
    }

    private var appsPage: some View {
        Form {
            if runningApps.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("没有运行中的应用", systemImage: "app.dashed")
                    }
                }
            } else {
                Section {
                    ForEach(runningApps, id: \.bundleID) { info in
                        Toggle(isOn: exclusionBinding(for: info)) {
                            Text(info.displayName)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsContentMargins()
        .navigationTitle("应用")
        .onAppear(perform: refreshRunningApps)
        .onChange(of: settingsPage) { _, page in
            if page == .apps {
                refreshRunningApps()
            }
        }
    }

    private var generalPage: some View {
        Form {
            Section {
                Toggle("在登录时启动 Vitals", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsContentMargins()
        .navigationTitle("通用")
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarIconEnabled },
            set: { enabled in
                menuBarIconEnabled = enabled
                AppSettings.shared.isMenuBarIconEnabled = enabled
            }
        )
    }

    private func displayBinding(_ item: DisplayItem) -> Binding<Bool> {
        Binding(
            get: { AppSettings.shared.enabledDisplayItems.contains(item) },
            set: { enabled in
                AppSettings.shared.setEnabled(item, enabled)
                menuBarIconEnabled = AppSettings.shared.isMenuBarIconEnabled
            }
        )
    }

    private func exclusionBinding(for info: RunningAppInfo) -> Binding<Bool> {
        let bundleID = info.bundleID
        return Binding(
            get: { AppSettings.shared.isExcluded(bundleID) },
            set: { AppSettings.shared.setExcluded(bundleID, $0) }
        )
    }

    private func refreshRunningApps() {
        runningApps = AppListSection.collectAll()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LaunchAtLogin.enable()
            } else {
                try LaunchAtLogin.disable()
            }
        } catch {
            print("[launch] error: \(error)")
        }
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }
}

private extension RunningAppInfo {
    var bundleID: String {
        app.bundleIdentifier ?? ""
    }
}
