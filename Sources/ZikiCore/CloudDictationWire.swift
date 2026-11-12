import Foundation
import CoreFoundation


public struct CloudDictationResult: Equatable, Sendable {
    public let text: String
    public let rawText: String
    public let billedSeconds: Double
    public let cleanupFailed: Bool
}

public enum CloudDictationWire {
    public struct Reservation: Decodable, Sendable {
        public let id: String
        public let maxSeconds: Int
        public let status: String
    }

    public enum Event: Sendable {
        case ready, hypothesis(String), segmentFinal(String), completed(CloudDictationResult), error(String)
    }

    public static func reservation(_ data: Data) throws -> Reservation {
        guard data.count <= 16_384 else { throw invalid }
        let value = try JSONDecoder().decode(Reservation.self, from: data)
        guard UUID(uuidString: value.id) != nil, (1...300).contains(value.maxSeconds),
              value.status == "reserved" else { throw invalid }
        return value
    }

    public static func event(_ data: Data, maximumSeconds: Int) throws -> Event {
        guard data.count <= 524_288,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { throw invalid }
        func text(_ key: String) throws -> String {
            guard let value = object[key] as? String, value.utf8.count <= 200_000 else { throw invalid }
            return value
        }
        switch type {
        case "ready": return .ready
        case "hypothesis": return .hypothesis(try text("text"))
        case "segmentFinal": return .segmentFinal(try text("text"))
        case "error":
            let code = try text("code")
            guard code.count <= 80, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw invalid }
            return .error(code)
        case "completed":
            guard let number = object["billedSeconds"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue <= Double(maximumSeconds),
                  let failedNumber = object["cleanupFailed"] as? NSNumber,
                  CFGetTypeID(failedNumber) == CFBooleanGetTypeID() else { throw invalid }
            return .completed(CloudDictationResult(text: try text("text"), rawText: try text("rawText"), billedSeconds: number.doubleValue, cleanupFailed: failedNumber.boolValue))
        default: throw invalid
        }
    }

    public static func acceptedBytes(_ count: Int, sent: Int, maximumSeconds: Int) -> Int {
        max(0, min(count, maximumSeconds * 32_000 - sent)) / 2 * 2
    }

    private static var invalid: ASRFailure {
        ASRFailure(kind: .provider, message: "Cloud 返回了无效响应", retryable: false)
    }
}
