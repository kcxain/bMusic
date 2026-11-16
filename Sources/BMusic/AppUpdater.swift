import Combine
import Sparkle

/// One updater owns scheduling, verification and installation for the application.
@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published var automaticallyChecks = true {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        URLProtocol.registerClass(UpdateProxyProtocol.self)
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheck)
        controller.startUpdater()
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func check() { controller.checkForUpdates(nil) }
}
