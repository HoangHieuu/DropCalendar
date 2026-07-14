import SwiftUI

@main
struct SnapCalApp: App {
    @NSApplicationDelegateAdaptor(SnapCalAppDelegate.self) private var appDelegate
    @State private var model = SnapCalModel.live()

    var body: some Scene {
        WindowGroup("SnapCal", id: "main") {
            SnapCalRootView(model: model, appDelegate: appDelegate)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)

        MenuBarExtra("SnapCal", systemImage: "calendar.badge.plus") {
            SnapCalMenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PrivacySettingsView(model: model)
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
