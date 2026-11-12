import AppKit
import SwiftUI

// Credentials stay on the configured authority, including on HTTP redirects.
private final class CloudRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class CloudAccount: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var availableSeconds: Int?
    @Published private(set) var code: String?
    @Published private(set) var busy = false
    @Published private(set) var hasSession = false
    @Published private(set) var message = "Sign in to use your Cloud allowance."
    private(set) var token: String?
    let origin: URL?
    private var pendingRevocation = false
    private let defaults: UserDefaults
    private static let revocationKey = "cloudPendingRevocationOrigin"
    private var task: Task<Void, Never>?
    private let send: (URLRequest) async throws -> (Data, Int)
    private let read: () async -> String?
    private let write: (String) async throws -> Void
    private let remove: () async throws -> Void
    private let openBrowser: (URL) -> Bool
    private let sleep: (Double) async throws -> Void

    static func validatedOrigin(_ value: String?, development: Bool) -> URL? {
        guard let value, let url = URL(string: value), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (development && url.scheme == "http" && host == "127.0.0.1") else { return nil }
        return URL(string: String(url.absoluteString.dropLast(url.absoluteString.hasSuffix("/") ? 1 : 0)))
    }

    init(
        origin: URL? = CloudAccount.validatedOrigin(Bundle.main.object(forInfoDictionaryKey: "ZikiCloudOrigin") as? String, development: AppEnvironment.isDevelopment),
        defaults: UserDefaults = AppEnvironment.userDefaults,
        send: ((URLRequest) async throws -> (Data, Int))? = nil,
        read: (() async -> String?)? = nil,
        write: ((String) async throws -> Void)? = nil,
        remove: (() async throws -> Void)? = nil,
        openBrowser: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.origin = origin
        self.defaults = defaults
        let keychain = KeychainStore()
        let session = URLSession(configuration: .ephemeral, delegate: CloudRedirectPolicy(), delegateQueue: nil)
        self.send = send ?? { request in
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        self.read = read ?? { await keychain.read(.cloudSession) }
        self.write = write ?? { try await keychain.write($0, for: .cloudSession) }
        self.remove = remove ?? { try await keychain.remove(.cloudSession) }
        self.openBrowser = openBrowser
        self.sleep = sleep
    }

    var canDictate: Bool { origin != nil && token != nil && email != nil && !pendingRevocation && !busy }
    private struct Failure: Error { let status: Int; let code: String }
    private struct Saved: Codable { let origin: String; let token: String; var pendingRevocation: Bool? }
    private struct Device: Decodable { let device_code: String; let user_code: String; let expires_in: Double; let interval: Double }
    private struct Access: Decodable { let access_token: String }
    private struct Account: Decodable { struct User: Decodable { let email: String }; let user: User; let availableSeconds: Int }

    private func request(_ path: String, body: [String: String]? = nil, token: String? = nil) async throws -> Data {
        guard let origin else { throw Failure(status: 0, code: "not_configured") }
        var request = URLRequest(url: origin.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, status) = try await send(request)
        guard data.count <= 65_536 else { throw Failure(status: 0, code: "invalid_response") }
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw Failure(status: status, code: json?["error"] as? String ?? "request_failed")
        }
        return data
    }

    private func save(_ token: String, pending: Bool) async throws {
        guard let origin else { throw Failure(status: 0, code: "not_configured") }
        try await write(String(decoding: JSONEncoder().encode(Saved(origin: origin.absoluteString, token: token, pendingRevocation: pending)), as: UTF8.self))
    }

    func restore() async {
        guard !busy, origin != nil else { return }
        busy = true
        defer { busy = false }
        if token == nil, let value = await read(), let data = value.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.origin == origin?.absoluteString, !saved.token.isEmpty {
            token = saved.token
            pendingRevocation = saved.pendingRevocation == true || defaults.string(forKey: Self.revocationKey) == origin?.absoluteString
            hasSession = true
        }
        guard let token else { return }
        if pendingRevocation { message = "A cancelled sign-in needs revocation. Choose Sign out to retry."; return }
        do { try await loadAccount(token) }
        catch let error as Failure where error.status == 401 {
            do { try await remove(); clearSession() }
            catch { pendingRevocation = true; email = nil; message = "Unable to remove the expired session from Keychain." }
        }
        catch { message = "Unable to refresh account. Try again when the service is available." }
    }

    private func loadAccount(_ token: String) async throws {
        let data = try await request("v1/me", token: token)
        let account = try JSONDecoder().decode(Account.self, from: data)
        guard !account.user.email.isEmpty, account.availableSeconds >= 0 else { throw Failure(status: 0, code: "invalid_response") }
        try Task.checkCancellation()
        email = account.user.email
        availableSeconds = account.availableSeconds
    }

    func cancel() { guard let task else { return }; task.cancel(); code = nil; message = "Cancelling sign-in…" }

    @discardableResult
    func signIn() -> Task<Void, Never>? {
        guard !busy, !hasSession else { return nil }
        guard let origin else { message = "Cloud service is not configured in this build."; return nil }
        busy = true
        let work = Task {
            defer { code = nil; busy = false; task = nil }
            do {
                let data = try await request("api/auth/device/code", body: ["client_id": "ziki-macos"])
                let device = try JSONDecoder().decode(Device.self, from: data)
                guard !device.device_code.isEmpty, device.device_code.count <= 1024,
                      !device.user_code.isEmpty, device.user_code.count <= 32,
                      device.expires_in.isFinite, (1...3600).contains(device.expires_in),
                      device.interval.isFinite, (1...60).contains(device.interval) else { throw Failure(status: 0, code: "invalid_response") }
                try Task.checkCancellation()
                code = device.user_code
                message = "Enter this code in your browser, verify it, and approve Ziki."
                guard openBrowser(origin.appendingPathComponent("device")) else { throw Failure(status: 0, code: "browser_unavailable") }
                let deadline = ContinuousClock.now.advanced(by: .seconds(device.expires_in))
                var delay = device.interval
                while ContinuousClock.now < deadline {
                    try await sleep(delay)
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { break }
                    do {
                        let data = try await request("api/auth/device/token", body: ["client_id": "ziki-macos", "device_code": device.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
                        let access = try JSONDecoder().decode(Access.self, from: data)
                        guard !access.access_token.isEmpty, access.access_token.count <= 8192 else { throw Failure(status: 0, code: "invalid_response") }
                        token = access.access_token
                        hasSession = true
                        pendingRevocation = true
                        defaults.set(origin.absoluteString, forKey: Self.revocationKey)
                        // Persist revocation intent before any cancellable account request.
                        try await save(access.access_token, pending: true)
                        try Task.checkCancellation()
                        try await loadAccount(access.access_token)
                        try await save(access.access_token, pending: false)
                        try Task.checkCancellation()
                        pendingRevocation = false
                        defaults.removeObject(forKey: Self.revocationKey)
                        message = "Signed in. Select Cloud to use this account."
                        return
                    } catch let error as Failure {
                        switch error.code {
                        case "authorization_pending": continue
                        case "slow_down": delay = min(delay + 5, 60)
                        case "access_denied": message = "Sign-in denied."; return
                        case "expired_token": message = "Sign-in expired. Start again."; return
                        default: throw error
                        }
                    }
                }
                message = "Sign-in expired. Start again."
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                if let token {
                    pendingRevocation = true
                    email = nil
                    availableSeconds = nil
                    // Unstructured cleanup survives cancellation of the polling task.
                    await Task { await self.revoke(token) }.value
                }
                if !hasSession { message = cancelled ? "Sign-in cancelled." : "Cloud sign-in failed. Please try again." }
            }
        }
        task = work
        return work
    }

    private func clearSession() { defaults.removeObject(forKey: Self.revocationKey); token = nil; email = nil; availableSeconds = nil; hasSession = false; pendingRevocation = false }
    private func revoke(_ token: String) async {
        defaults.set(origin?.absoluteString, forKey: Self.revocationKey)
        do {
            // Keep cancellation durable even if revocation is temporarily unavailable.
            try? await save(token, pending: true)
            do { _ = try await request("api/auth/sign-out", body: [:], token: token) }
            catch let error as Failure where error.status == 401 { }
            try await remove()
            clearSession()
            message = "Signed out."
        } catch { message = "Could not revoke the session. Retry Sign out when the service is available." }
    }
    func signOut() async {
        guard !busy, let token else { return }
        busy = true
        pendingRevocation = true
        email = nil
        availableSeconds = nil
        defer { busy = false }
        await revoke(token)
    }
}

struct CloudAccountSettingsView: View {
    @ObservedObject var account: CloudAccount
    var body: some View {
        Section("Cloud account") {
            if let email = account.email { Text(email) }
            if let seconds = account.availableSeconds { Text("Available: \(seconds / 60)m \(seconds % 60)s") }
            if account.hasSession {
                Button("Refresh allowance") { Task { await account.restore() } }.disabled(account.busy)
                Button("Sign out and revoke session") { Task { await account.signOut() } }.disabled(account.busy)
            } else if account.busy {
                if let code = account.code { Text(code).font(.title.monospaced()).textSelection(.enabled) }
                Button("Cancel sign-in") { account.cancel() }
            } else { Button("Sign in using browser") { account.signIn() }.disabled(account.origin == nil) }
            Text(account.message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
