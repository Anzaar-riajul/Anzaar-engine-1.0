import AppKit
import Foundation

public final class MacAppUpdater: ObservableObject {
    public static let shared = MacAppUpdater()

    private let repoOwner = "Anzaar-riajul"
    private let repoName = "Anzaar-engine-1.0"

    @Published public var hasUpdate: Bool = false
    @Published public var latestVersion: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var downloadUrl: String? = nil
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var statusMessage: String = ""

    private var checkTimer: Timer?
    private let currentBuildNumber: Int = {
        let info = Bundle.main.infoDictionary
        let buildStr = info?["CFBundleVersion"] as? String ?? "81"
        return Int(buildStr) ?? 81
    }()

    private init() {}

    public func start() {
        checkForUpdates()
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    public func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Techuboard-macOS-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawTag = json["tag_name"] as? String else { return }

                let body = json["body"] as? String ?? ""
                let assets = json["assets"] as? [[String: Any]] ?? []

                var macUrl: String? = nil
                for asset in assets {
                    let name = (asset["name"] as? String ?? "").lowercased()
                    if name.hasSuffix(".dmg") || name.hasSuffix(".zip") || name.contains("mac") {
                        macUrl = asset["browser_download_url"] as? String
                        break
                    }
                }

                // If no direct mac binary in assets, fallback to release page
                let finalUrl = macUrl ?? (json["html_url"] as? String ?? "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/latest")

                let remoteBuild = self.extractBuildNumber(rawTag)
                let isNewer = remoteBuild > self.currentBuildNumber

                DispatchQueue.main.async {
                    self.latestVersion = rawTag
                    self.releaseNotes = body
                    self.downloadUrl = finalUrl
                    self.hasUpdate = isNewer

                    if isNewer {
                        self.showUpdateNotification(tag: rawTag)
                    }
                }
            } catch {
                NSLog("[MacAppUpdater] JSON error: \(error)")
            }
        }.resume()
    }

    private func extractBuildNumber(_ tag: String) -> Int {
        // Tag formats like "android-v1.0-85" or "native-v1.0-35" or "v1.0-85"
        let parts = tag.components(separatedBy: "-")
        if let last = parts.last, let num = Int(last.filter { $0.isNumber }) {
            return num
        }
        return 0
    }

    private func showUpdateNotification(tag: String) {
        let notification = NSUserNotification()
        notification.title = "🚀 Techuboard Update Required"
        notification.informativeText = "Version \(tag) is available. Please update now to maintain sync compatibility."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    public func execute1ClickUpdate() {
        guard let urlString = downloadUrl, let url = URL(string: urlString) else { return }

        // Open direct download or release installer
        NSWorkspace.shared.open(url)
    }
}
