import SwiftUI

struct GeneralSettings: View {
    @Bindable var settings = AppSettings.shared
    let launchAtLogin: LaunchAtLogin
    @State private var trusted = AXWindows.isTrusted

    var body: some View {
        Form {
            if !trusted {
                Section {
                    Label("GridLock can't move windows yet. Turn on GridLock in Privacy & Security › Device Control and Data Access.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Privacy Settings") { WelcomeWindow.shared.show() }
                }
            }
            EdgeTilingNote()
            Section {
                AppearancePicker()
                Caption(AppAppearance.footer(appName: "GridLock"))
            }
            Section {
                Toggle("Open GridLock at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    HStack {
                        Caption("Waiting for approval in Login Items.")
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }.controlSize(.small)
                    }
                }
                Toggle("Ask before quitting", isOn: $settings.confirmQuit)
                    .help("Quitting GridLock asks first, so a stray ⌘Q doesn't turn off the palette and shortcuts.")
            }
            Section {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .help("Adds a Dock icon whose right-click menu opens Settings.")
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                if !settings.showInDock && !settings.showInMenuBar {
                    Caption(AppPresence.hiddenEverywhereNote(appName: "GridLock", settingsName: "Settings"))
                }
            }
            Section {
                LabeledContent("Version", value: AppInfo.displayVersion)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refresh()
            trusted = AXWindows.isTrusted
        }
    }
}
