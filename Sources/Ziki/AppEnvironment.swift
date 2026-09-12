import Foundation

enum AppEnvironment {
    private static let developmentMarkerKey = "ZikiDevelopmentVariant"
    private static let productionApplicationSupportName = "Sotto"
    private static let developmentApplicationSupportName = "Sotto-Dev"

    static var isDevelopment: Bool {
        Bundle.main.object(forInfoDictionaryKey: developmentMarkerKey) as? Bool
            == true
    }

    static var userDefaults: UserDefaults {
        guard isDevelopment else { return .standard }
        guard let defaults = UserDefaults(suiteName: "com.willhong.sotto.dev")
        else {
            fatalError("Unable to initialize the isolated Ziki development defaults suite")
        }
        return defaults
    }

    static var keychainService: String {
        isDevelopment
            ? "com.sotto.voice.credentials.dev"
            : "com.sotto.voice.credentials"
    }

    static var applicationSupportDirectory: URL {
        let name = isDevelopment
            ? developmentApplicationSupportName
            : productionApplicationSupportName
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(name, isDirectory: true)
    }

    static var historyFileURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "dictation-history.json"
        )
    }

    static var diagnosticsDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "Diagnostics",
            isDirectory: true
        )
    }

    static var updaterEnabled: Bool {
        !isDevelopment
    }
}
