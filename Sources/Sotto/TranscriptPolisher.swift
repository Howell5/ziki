import Foundation
import SottoCore

enum TranscriptPolisherError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case provider(statusCode: Int, message: String)
    case emptyResponse
    case truncatedResponse(partialText: String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "整理服务 Endpoint 无效"
        case .badResponse:
            "整理服务返回了无法识别的响应"
        case let .provider(statusCode, message):
            "整理服务错误（\(statusCode)）：\(message)"
        case .emptyResponse:
            "整理服务没有返回文字"
        case .truncatedResponse:
            "整理服务的输出达到长度上限"
        }
    }
}

actor TranscriptPolisher {
    private struct ErrorBody: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let message: String?
        }

        let error: Detail?
    }

    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession

    init(
        route: BailianCleanupRoute,
        apiKey: String,
        session: URLSession = .shared
    ) {
        endpoint = route.endpoint
        self.apiKey = apiKey
        self.session = session
    }

    func polish(
        _ rawTranscript: String,
        context: [DictationContext.Turn] = []
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        request.httpBody = try BailianCleanupWire.makeRequest(
            rawTranscript: rawTranscript,
            context: context
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptPolisherError.badResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? JSONDecoder().decode(ErrorBody.self, from: data))?
                .error?.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw TranscriptPolisherError.provider(
                statusCode: httpResponse.statusCode,
                message: providerMessage
            )
        }

        let result: BailianCleanupResponse
        do {
            result = try BailianCleanupWire.decodeResponse(data)
        } catch BailianCleanupWireError.emptyResponse {
            throw TranscriptPolisherError.emptyResponse
        } catch {
            throw TranscriptPolisherError.badResponse
        }
        if result.wasTruncated {
            throw TranscriptPolisherError.truncatedResponse(
                partialText: result.text
            )
        }
        return result.text
    }

}
