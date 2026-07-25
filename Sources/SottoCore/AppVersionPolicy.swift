import Foundation

public enum AppVersionPolicy {
    public static func displayVersion(
        shortVersion: String?,
        buildNumber: String?,
        commitHash: String?
    ) -> String {
        let version = nonEmpty(shortVersion) ?? "未知版本"
        var parts = [version]
        if let build = nonEmpty(buildNumber) {
            parts[0] = "\(version) (\(build))"
        }
        if let commit = nonEmpty(commitHash) {
            parts.append(commit)
        }
        return parts.joined(separator: " · ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
