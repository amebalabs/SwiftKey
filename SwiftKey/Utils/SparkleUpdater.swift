import Sparkle

final class SparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    
    static let shared: SparkleUpdater = {
        guard Thread.isMainThread else {
            fatalError("SparkleUpdater must be initialized on the main thread")
        }
        return SparkleUpdater()
    }()
    
    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.clearFeedURLFromUserDefaults()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        configureFeedURLs()
        controller.startUpdater()
    }
    
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
    
    func configureFeedURLs() {
        let defaults = UserDefaults.standard
        let isBetaEnabled = defaults.bool(forKey: "EnableBetaUpdates")
        
        let baseURL = "https://amebalabs.github.io/swiftkey"
        let feedURL = isBetaEnabled ?
        "\(baseURL)/appcast_beta.xml" :
        "\(baseURL)/appcast.xml"
        
        defaults.set(feedURL, forKey: "SUFeedURL")
        defaults.synchronize()
    }
    
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
}
