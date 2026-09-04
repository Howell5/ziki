import AppKit
import CryptoKit
import Foundation
import SottoCore

enum AppUpdateState: Equatable {
    case idle
    case checking
    case current(version: String)
    case available(AppUpdatePackage)
    case downloading(version: String)
    case preparing(version: String)
    case failed(message: String)
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle

    private let service = AppUpdateService()
    private var task: Task<Void, Never>?

    init() {
        let errorURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Sotto/Updates/last-error.txt")
        if FileManager.default.fileExists(atPath: errorURL.path) {
            state = .failed(
                message: "上次更新未完成，原版本已保留。请重新检查更新。"
            )
            try? FileManager.default.removeItem(at: errorURL)
        }
    }

    func check() {
        task?.cancel()
        state = .checking
        task = Task {
            do {
                let availability = try await service.check(
                    currentVersion: currentVersion,
                    architecture: currentArchitecture
                )
                guard !Task.isCancelled else { return }
                switch availability {
                case let .current(version):
                    state = .current(version: version)
                case let .available(package):
                    state = .available(package)
                }
            } catch is CancellationError {
                return
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func install() {
        guard case let .available(package) = state else { return }
        task?.cancel()
        state = .downloading(version: package.version)
        task = Task {
            do {
                let prepared = try await service.prepare(
                    package,
                    replacing: Bundle.main.bundleURL
                )
                guard !Task.isCancelled else { return }
                state = .preparing(version: package.version)
                try await service.launchInstaller(
                    prepared,
                    replacing: Bundle.main.bundleURL,
                    parentPID: ProcessInfo.processInfo.processIdentifier
                )
                NSApp.terminate(nil)
            } catch is CancellationError {
                return
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
    }

    private var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }
}

private struct PreparedUpdate: Sendable {
    let applicationURL: URL
    let workingDirectoryURL: URL
}

private enum AppUpdateError: LocalizedError {
    case invalidServerResponse
    case packageTooLarge
    case downloadIncomplete
    case checksumMismatch
    case invalidApplication
    case versionMismatch
    case signatureMismatch
    case installationUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            "无法读取 GitHub Release"
        case .packageTooLarge:
            "更新包大小异常"
        case .downloadIncomplete:
            "更新包下载不完整"
        case .checksumMismatch:
            "更新包校验失败，已停止安装"
        case .invalidApplication:
            "更新包中的 Sotto.app 无效"
        case .versionMismatch:
            "更新包版本与 Release 不一致"
        case .signatureMismatch:
            "更新包签名与当前 Sotto 不一致，已停止安装"
        case .installationUnavailable:
            "当前安装位置不可更新，请先把 Sotto 放入“应用程序”文件夹"
        case let .commandFailed(command):
            "更新准备失败：\(command)"
        }
    }
}

private actor AppUpdateService {
    private static let releaseURL = URL(
        string: "https://api.github.com/repos/Howell5/sotto/releases/latest"
    )!
    private static let maximumPackageSize = 200 * 1_024 * 1_024

    func check(
        currentVersion: String,
        architecture: String
    ) async throws -> AppUpdateAvailability {
        var request = URLRequest(url: Self.releaseURL)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2026-03-10",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        request.setValue("Sotto/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw AppUpdateError.invalidServerResponse
        }
        do {
            return try AppUpdatePolicy.resolve(
                releaseData: data,
                currentVersion: currentVersion,
                architecture: architecture
            )
        } catch let error as AppUpdatePolicyError {
            switch error {
            case .invalidRelease:
                throw AppUpdateError.invalidServerResponse
            case .missingPackage:
                throw AppUpdateError.invalidApplication
            case .missingDigest:
                throw AppUpdateError.checksumMismatch
            }
        }
    }

    func prepare(
        _ package: AppUpdatePackage,
        replacing installedApplicationURL: URL
    ) async throws -> PreparedUpdate {
        guard package.size > 0,
              package.size <= Self.maximumPackageSize
        else {
            throw AppUpdateError.packageTooLarge
        }
        let parentURL = installedApplicationURL.deletingLastPathComponent()
        guard installedApplicationURL.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: parentURL.path)
        else {
            throw AppUpdateError.installationUnavailable
        }

        let workingDirectoryURL = try makeWorkingDirectory()
        var keepWorkingDirectory = false
        defer {
            if !keepWorkingDirectory {
                try? FileManager.default.removeItem(at: workingDirectoryURL)
            }
        }

        let (temporaryURL, response) = try await URLSession.shared.download(
            from: package.downloadURL
        )
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw AppUpdateError.invalidServerResponse
        }

        let archiveURL = workingDirectoryURL.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: archiveURL.path
        )
        guard attributes[.size] as? Int == package.size else {
            throw AppUpdateError.downloadIncomplete
        }
        guard try sha256(of: archiveURL) == package.sha256 else {
            throw AppUpdateError.checksumMismatch
        }

        let extractionURL = workingDirectoryURL.appendingPathComponent(
            "extracted",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extractionURL,
            withIntermediateDirectories: true
        )
        _ = try run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )

        let candidateURL = extractionURL.appendingPathComponent(
            "Sotto.app",
            isDirectory: true
        )
        let candidateValues = try candidateURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard candidateValues.isDirectory == true,
              candidateValues.isSymbolicLink != true,
              let candidateBundle = Bundle(url: candidateURL),
              candidateBundle.bundleIdentifier == "com.willhong.sotto",
              candidateBundle.executableURL != nil
        else {
            throw AppUpdateError.invalidApplication
        }
        guard candidateBundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String == package.version else {
            throw AppUpdateError.versionMismatch
        }

        _ = try run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", candidateURL.path]
        )
        let installedRequirement = try designatedRequirement(
            for: installedApplicationURL
        )
        let candidateRequirement = try designatedRequirement(for: candidateURL)
        guard installedRequirement == candidateRequirement else {
            throw AppUpdateError.signatureMismatch
        }

        keepWorkingDirectory = true
        return PreparedUpdate(
            applicationURL: candidateURL,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    func launchInstaller(
        _ update: PreparedUpdate,
        replacing installedApplicationURL: URL,
        parentPID: Int32
    ) throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/SottoUpdater")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw AppUpdateError.installationUnavailable
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            String(parentPID),
            update.applicationURL.path,
            installedApplicationURL.path,
            update.workingDirectoryURL.path
        ]
        try process.run()
    }

    private func makeWorkingDirectory() throws -> URL {
        let rootURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Sotto/Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let workingURL = rootURL.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workingURL,
            withIntermediateDirectories: false
        )
        return workingURL
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_024 * 1_024),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func designatedRequirement(for applicationURL: URL) throws -> String {
        let output = try run(
            "/usr/bin/codesign",
            arguments: ["-d", "-r-", applicationURL.path]
        )
        guard let requirement = output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("designated =>") })
        else {
            throw AppUpdateError.signatureMismatch
        }
        return String(requirement)
    }

    @discardableResult
    private func run(
        _ executable: String,
        arguments: [String]
    ) throws -> String {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.commandFailed(
                URL(fileURLWithPath: executable).lastPathComponent
            )
        }
        return output
    }
}
