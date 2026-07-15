import Foundation
import Sparkle

@MainActor
final class AppUpdateController {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let feed,
              let publicKey,
              URL(string: feed)?.scheme == "https",
              !publicKey.isEmpty,
              publicKey != "UNCONFIGURED" else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var isConfigured: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
