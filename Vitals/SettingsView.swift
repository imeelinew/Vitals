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
            case .menubar: return "menubar.rectangle"
            case .apps: return "square.grid.2x2.fill"
            case .general: return "gearshape.fill"
            }
        }

        var professionalIconResourceName: String {
            switch self {
            case .menubar: return "app-window"
            case .apps: return "folder-bookmark"
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
        .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
        .background {
            WindowTransparencyConfigurator(enabled: false)
                .frame(width: 0, height: 0)
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
                Toggle(isOn: displayBinding(.cpu)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CPU")
                        Text(DisplayItem.cpu.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: displayBinding(.memory)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("内存")
                        Text(DisplayItem.memory.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: displayBinding(.pressure)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("压力")
                        Text(DisplayItem.pressure.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("至少保留一项显示在菜单栏")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.automatic)
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
                } footer: {
                    Text("隐藏不想在菜单栏应用列表中看到的应用")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.automatic)
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
                Toggle(isOn: $launchAtLoginEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开机启动")
                        Text("登录时自动启动 Vitals")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchAtLoginEnabled) { _, enabled in
                    updateLaunchAtLogin(enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.automatic)
        .settingsContentMargins()
        .navigationTitle("通用")
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private func displayBinding(_ item: DisplayItem) -> Binding<Bool> {
        Binding(
            get: { AppSettings.shared.isEnabled(item) },
            set: { AppSettings.shared.setEnabled(item, $0) }
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
