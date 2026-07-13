import SwiftUI

@main
struct SnapCalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)
    }
}
