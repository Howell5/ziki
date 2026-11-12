// Run with ASRSession.swift + CloudASRSession.swift and the built ZikiCore module.
import Foundation
import ZikiCore

private actor LostReservationFixture {
    private let id = UUID().uuidString.lowercased()
    private let losesResponse: Bool
    init(losesResponse: Bool = true) { self.losesResponse = losesResponse }
    private var requests: [URLRequest] = []
    private var cancellations: [Bool] = []
    private var initialWaiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        cancellations.append(Task.isCancelled)
        if requests.count == 1 {
            await withCheckedContinuation { continuation in
                initialWaiter = continuation
                observer?.resume(); observer = nil
            }
            // Simulates DB commit followed by a response lost to runner cancellation.
            if losesResponse { throw URLError(.networkConnectionLost) }
        }
        let body: Data
        if request.url!.path.hasSuffix("/cancel") { body = Data("{}".utf8) }
        else { body = Data("{\"id\":\"\(id)\",\"maxSeconds\":2,\"status\":\"reserved\"}".utf8) }
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func waitForInitial() async {
        if initialWaiter != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func loseResponse() { initialWaiter?.resume(); initialWaiter = nil }
    func verify() throws {
        assert(requests.count == (losesResponse ? 3 : 2))
        assert(requests[0].url!.path == "/v1/dictations")
        if losesResponse {
            assert(requests[1].url!.path == "/v1/dictations")
            assert(requests[0].httpBody == requests[1].httpBody)
        }
        let payload = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
        assert(UUID(uuidString: payload["idempotencyKey"] as! String) != nil)
        assert(requests.last!.url!.path == "/v1/dictations/\(id)/cancel")
        assert(cancellations.dropFirst().allSatisfy { !$0 })
    }
}

@main struct CloudSessionChecks {
    static func rejects(_ body: () throws -> Void) {
        do { try body(); fatalError("Expected invalid wire data to be rejected") }
        catch { }
    }

    static func main() async throws {
        let id = UUID().uuidString
        let good = Data("{\"id\":\"\(id)\",\"maxSeconds\":2,\"status\":\"reserved\"}".utf8)
        let reservation = try CloudDictationWire.reservation(good)
        assert(reservation.maxSeconds == 2)
        for value in ["0", "301", "1.5", "true"] {
            rejects { _ = try CloudDictationWire.reservation(Data("{\"id\":\"\(id)\",\"maxSeconds\":\(value),\"status\":\"reserved\"}".utf8)) }
        }
        for status in ["processing", "completed", "cancelled"] {
            rejects { _ = try CloudDictationWire.reservation(Data("{\"id\":\"\(id)\",\"maxSeconds\":2,\"status\":\"\(status)\"}".utf8)) }
        }
        rejects { _ = try CloudDictationWire.reservation(Data("{\"id\":\"../other-user\",\"maxSeconds\":2,\"status\":\"reserved\"}".utf8)) }
        func completed(_ seconds: String, _ failed: String = "false") -> Data {
            Data("{\"type\":\"completed\",\"text\":\"clean\",\"rawText\":\"raw\",\"billedSeconds\":\(seconds),\"cleanupFailed\":\(failed)}".utf8)
        }
        if case let .completed(result) = try CloudDictationWire.event(completed("1.25"), maximumSeconds: 2) {
            assert(result.text == "clean" && result.rawText == "raw" && result.billedSeconds == 1.25)
        } else { fatalError("Missing completed result") }
        for value in ["-1", "3", "true", "null", "\"1\""] {
            rejects { _ = try CloudDictationWire.event(completed(value), maximumSeconds: 2) }
        }
        rejects { _ = try CloudDictationWire.event(completed("1", "1"), maximumSeconds: 2) }
        rejects { _ = try CloudDictationWire.event(Data("{\"type\":\"error\",\"code\":\"credential leaked\"}".utf8), maximumSeconds: 2) }
        rejects { _ = try CloudDictationWire.event(Data("{\"type\":\"hypothesis\",\"text\":\"\(String(repeating: "a", count: 200_001))\"}".utf8), maximumSeconds: 2) }
        assert(CloudDictationWire.acceptedBytes(32_000, sent: 0, maximumSeconds: 2) == 32_000)
        assert(CloudDictationWire.acceptedBytes(32_000, sent: 63_998, maximumSeconds: 2) == 2)
        assert(CloudDictationWire.acceptedBytes(32_000, sent: 64_000, maximumSeconds: 2) == 0)
        assert(CloudDictationWire.acceptedBytes(3, sent: 0, maximumSeconds: 2) == 2)
        let session = CloudASRSession(origin: URL(string: "http://invalid.example")!, token: "test", cleanupEnabled: false, context: [], onLimitReached: {})
        do { try await session.start(configuration: ASRConfiguration()); fatalError("Accepted insecure origin") }
        catch let error as ASRFailure { assert(error.kind == .badInput) }
        do { try await session.finish(); fatalError("Finished idle session") } catch { }
        await session.cancel()
        await session.cancel()
        let result = await session.result()
        assert(result == nil)
        do { try await session.start(configuration: ASRConfiguration()); fatalError("Restarted cancelled session") } catch { }
        do { try await session.sendPCM16(Data([0, 0])); fatalError("Sent PCM on cancelled session") } catch { }
        do { try await session.finish(); fatalError("Finished cancelled session") } catch { }
        var eventCount = 0
        for try await _ in session.eventStream() { eventCount += 1 }
        assert(eventCount == 0)
        for cancelRunner in [false, true] {
            let fixture = LostReservationFixture()
            let recovering = CloudASRSession(origin: URL(string: "https://fixture.invalid")!, token: "fixture",
                cleanupEnabled: false, context: [], onLimitReached: {},
                metadataRequest: { try await fixture.send($0) })
            let runner = Task { try await recovering.start(configuration: ASRConfiguration()) }
            await fixture.waitForInitial()
            if cancelRunner {
                runner.cancel()
                await recovering.cancel()
            }
            await fixture.loseResponse()
            do { try await runner.value; fatalError("Lost reserve response unexpectedly started a socket") } catch { }
            try await fixture.verify()
            await recovering.cancel()
            try await fixture.verify() // release is deduplicated after recovery.
        }
        let delivered = LostReservationFixture(losesResponse: false)
        let cancelled = CloudASRSession(origin: URL(string: "https://fixture.invalid")!, token: "fixture",
            cleanupEnabled: false, context: [], onLimitReached: {}, metadataRequest: { try await delivered.send($0) })
        let cancelledRunner = Task { try await cancelled.start(configuration: ASRConfiguration()) }
        await delivered.waitForInitial()
        cancelledRunner.cancel()
        await cancelled.cancel()
        await delivered.loseResponse()
        do { try await cancelledRunner.value; fatalError("Cancelled reserve opened a socket") } catch { }
        try await delivered.verify()
        print("Cloud parser, byte limits, states, and lost-reservation recovery checks passed")
    }
}
