import Foundation

@main
struct CloudAccountChecks {
    @MainActor static func main() async throws {
        let suite = "ziki-cloud-checks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let origin = URL(string: "https://cloud.example.invalid")!
        precondition(CloudAccount.validatedOrigin("https://example.com/", development: false)?.absoluteString == "https://example.com")
        for value in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?token=x", "http://127.0.0.1:8787"] {
            precondition(CloudAccount.validatedOrigin(value, development: false) == nil)
        }
        precondition(CloudAccount.validatedOrigin("http://127.0.0.1:8787", development: true) != nil)
        var stored: String?
        var polls = 0
        var delays: [Double] = []
        var failRevocation = false
        var cancelWhileSaving = false
        var target: CloudAccount?
        var revocations = 0
        let account = CloudAccount(origin: origin, defaults: defaults, send: { request in
            precondition(request.value(forHTTPHeaderField: "Origin") == origin.absoluteString)
            let path = request.url!.path
            let json: String
            var status = 200
            switch path {
            case "/api/auth/device/code":
                json = "{\"device_code\":\"device\",\"user_code\":\"12345678\",\"expires_in\":300,\"interval\":5}"
            case "/api/auth/device/token":
                polls += 1
                if polls == 1 { json = "{\"error\":\"authorization_pending\"}"; status = 400 }
                else if polls == 2 { json = "{\"error\":\"slow_down\"}"; status = 400 }
                else { json = "{\"access_token\":\"fixture-only-token\"}" }
            case "/v1/me":
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only-token")
                json = "{\"user\":{\"email\":\"test@example.invalid\"},\"availableSeconds\":45}"
            case "/api/auth/sign-out":
                revocations += 1
                if failRevocation { throw URLError(.notConnectedToInternet) }
                json = "{}"
            default: preconditionFailure("unexpected request")
            }
            return (Data(json.utf8), status)
        }, read: { stored }, write: { value in
            stored = value
            if cancelWhileSaving { cancelWhileSaving = false; target?.cancel() }
        }, remove: { stored = nil }, openBrowser: { url in
            precondition(url.absoluteString == "https://cloud.example.invalid/device"); return true
        }, sleep: { delays.append($0) })
        target = account
        let first = account.signIn()
        precondition(account.signIn() == nil)
        await first?.value
        precondition(account.email == "test@example.invalid" && account.availableSeconds == 45 && account.canDictate)
        precondition(delays == [5,5,10])
        failRevocation = true
        await account.signOut()
        precondition(account.hasSession && !account.canDictate && stored != nil)
        failRevocation = false
        await account.signOut()
        precondition(!account.hasSession && stored == nil)
        cancelWhileSaving = true
        await account.signIn()?.value
        precondition(!account.hasSession && !account.canDictate && stored == nil)
        precondition(account.message == "Sign-in cancelled.")
        precondition(revocations == 3)
        // A cancelled login whose revocation failed must remain explicitly revocable after restart.
        cancelWhileSaving = true
        failRevocation = true
        await account.signIn()?.value
        precondition(account.hasSession && !account.canDictate && stored != nil)
        let restored = CloudAccount(origin: origin, defaults: defaults, send: { _ in preconditionFailure("pending revoke must not fetch account") }, read: { stored }, write: { stored = $0 }, remove: { stored = nil })
        await restored.restore()
        precondition(restored.hasSession && !restored.canDictate && restored.email == nil)
        let foreign = CloudAccount(origin: URL(string: "https://other.example.invalid"), defaults: defaults, send: { _ in preconditionFailure("foreign token must not leave Keychain") }, read: { stored })
        await foreign.restore()
        precondition(!foreign.hasSession)
        stored = "{\"origin\":\"https://cloud.example.invalid\",\"token\":\"fixture-only-token\",\"pendingRevocation\":false}"
        defaults.removeObject(forKey: "cloudPendingRevocationOrigin")
        let failedWrite = CloudAccount(origin: origin, defaults: defaults, send: { request in
            if request.url!.path == "/v1/me" { return (Data("{\"user\":{\"email\":\"test@example.invalid\"},\"availableSeconds\":45}".utf8),200) }
            throw URLError(.notConnectedToInternet)
        }, read: { stored }, write: { _ in throw URLError(.cannotWriteToFile) }, remove: { stored = nil })
        await failedWrite.restore()
        precondition(failedWrite.canDictate)
        await failedWrite.signOut()
        let afterRestart = CloudAccount(origin: origin, defaults: defaults, send: { _ in preconditionFailure("revocation tombstone must block restoration") }, read: { stored })
        await afterRestart.restore()
        precondition(afterRestart.hasSession && !afterRestart.canDictate)
        print("Cloud account checks passed: origin, polling/backoff, concurrent login, cancellation, revocation retry, restart and authority isolation")
    }
}
