import SwiftUI

@main
struct SnapCalApp: App {
    @NSApplicationDelegateAdaptor(SnapCalAppDelegate.self) private var appDelegate
    @State private var model = SnapCalModel.live()
    private let updates = AppUpdateController()

    var body: some Scene {
        WindowGroup("SnapCal", id: "main") {
            SnapCalRootView(model: model, appDelegate: appDelegate)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            SnapCalMenuBarView(model: model, updates: updates)
        } label: {
            Image(systemName: "calendar.badge.plus")
                .accessibilityLabel("SnapCal")
                .accessibilityIdentifier("snapCalMenuBarStatusItem")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SnapCalSettingsView(model: model)
        }
    }

}

private struct SnapCalRootView: View {
    let model: SnapCalModel
    let appDelegate: SnapCalAppDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(model: model)
            .onAppear {
                appDelegate.installNotchDropZone(model: model) {
                    openWindow(id: "main")
                }
            }
    }
}
