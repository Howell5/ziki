import Darwin
import Foundation

private enum InstallerError: Error {
    case invalidArguments
    case parentDidNotExit
    case invalidApplication
    case signatureMismatch
    case commandFailed
}

private func run(_ executable: String, arguments: [String]) throws -> String {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(
        data: pipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    guard process.terminationStatus == 0 else {
        throw InstallerError.commandFailed
    }
    return output
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
        throw InstallerError.signatureMismatch
    }
    return String(requirement)
}

private func waitForExit(of pid: pid_t) throws {
    for _ in 0..<300 {
        if kill(pid, 0) != 0, errno == ESRCH {
            return
        }
        usleep(100_000)
    }
    throw InstallerError.parentDidNotExit
}

private func recordFailure(_ error: Error) {
    let fileManager = FileManager.default
    let errorURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    .appendingPathComponent("Sotto/Updates/last-error.txt")
    try? String(describing: error).write(
        to: errorURL,
        atomically: true,
        encoding: .utf8
    )
}

private func install() throws {
    let fileManager = FileManager.default
    let arguments = CommandLine.arguments
    guard arguments.count == 5,
          let parentPID = pid_t(arguments[1])
    else {
        throw InstallerError.invalidArguments
    }

    let sourceURL = URL(fileURLWithPath: arguments[2])
        .standardizedFileURL
    let destinationURL = URL(fileURLWithPath: arguments[3])
        .standardizedFileURL
    let workingDirectoryURL = URL(fileURLWithPath: arguments[4])
        .standardizedFileURL
    let updatesRootURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    .appendingPathComponent("Sotto/Updates", isDirectory: true)
    .standardizedFileURL

    guard workingDirectoryURL.path.hasPrefix(updatesRootURL.path + "/"),
          sourceURL.path.hasPrefix(workingDirectoryURL.path + "/"),
          destinationURL.pathExtension == "app",
          Bundle(url: sourceURL)?.bundleIdentifier == "com.willhong.sotto",
          Bundle(url: destinationURL)?.bundleIdentifier == "com.willhong.sotto",
          try designatedRequirement(for: sourceURL)
            == designatedRequirement(for: destinationURL)
    else {
        throw InstallerError.invalidApplication
    }

    try waitForExit(of: parentPID)

    let backupURL = workingDirectoryURL.appendingPathComponent(
        "previous.app",
        isDirectory: true
    )
    try fileManager.moveItem(at: destinationURL, to: backupURL)
    do {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        _ = try run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", destinationURL.path]
        )
    } catch {
        if fileManager.fileExists(atPath: destinationURL.path) {
            let failedURL = workingDirectoryURL.appendingPathComponent(
                "failed.app",
                isDirectory: true
            )
            try? fileManager.moveItem(at: destinationURL, to: failedURL)
        }
        try? fileManager.moveItem(at: backupURL, to: destinationURL)
        throw error
    }

    try? fileManager.removeItem(at: backupURL)
    try? fileManager.removeItem(at: workingDirectoryURL)
}

do {
    try install()
} catch {
    recordFailure(error)
    exit(EXIT_FAILURE)
}
