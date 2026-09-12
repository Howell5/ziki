import Foundation

public struct AppUpdatePackage: Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let size: Int

    public init(
        version: String,
        downloadURL: URL,
        sha256: String,
        size: Int
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.size = size
    }
}

public enum AppUpdateAvailability: Equatable, Sendable {
    case current(latestVersion: String)
    case available(AppUpdatePackage)
}

public enum AppUpdatePolicyError: Error, Equatable, Sendable {
    case invalidRelease
    case missingPackage
    case missingDigest
}

public enum AppUpdatePolicy {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let digest: String?
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case size
                case digest
                case browserDownloadURL = "browser_download_url"
            }

            var downloadURLIsTrusted: Bool {
                browserDownloadURL.scheme == "https"
                    && browserDownloadURL.host == "github.com"
                    && browserDownloadURL.path.hasPrefix(
                        "/Howell5/sotto/releases/download/"
                    )
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    public static func resolve(
        releaseData: Data,
        currentVersion: String,
        architecture: String
    ) throws -> AppUpdateAvailability {
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: releaseData)
        } catch {
            throw AppUpdatePolicyError.invalidRelease
        }

        guard let latest = Version(release.tagName),
              let current = Version(currentVersion)
        else {
            throw AppUpdatePolicyError.invalidRelease
        }
        guard latest > current else {
            return .current(latestVersion: latest.description)
        }

        let packageName =
            "Ziki-\(latest.description)-macOS-\(architecture).zip"
        guard let asset = release.assets.first(where: { $0.name == packageName }),
              asset.downloadURLIsTrusted
        else {
            throw AppUpdatePolicyError.missingPackage
        }
        guard let digest = asset.digest?.lowercased(),
              digest.hasPrefix("sha256:"),
              digest.dropFirst(7).count == 64,
              digest.dropFirst(7).allSatisfy(\.isHexDigit)
        else {
            throw AppUpdatePolicyError.missingDigest
        }

        return .available(
            AppUpdatePackage(
                version: latest.description,
                downloadURL: asset.browserDownloadURL,
                sha256: String(digest.dropFirst(7)),
                size: asset.size
            )
        )
    }
}

private struct Version: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ value: String) {
        let normalized = value.hasPrefix("v")
            ? String(value.dropFirst())
            : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        parts = components.compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
    }

    var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
