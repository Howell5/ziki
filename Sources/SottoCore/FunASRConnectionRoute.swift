import Foundation

public enum FunASRServiceRegion: Equatable, Sendable {
    case mainlandChina
    case singapore

    fileprivate var workspaceHostSuffix: String {
        switch self {
        case .mainlandChina:
            "cn-beijing.maas.aliyuncs.com"
        case .singapore:
            "ap-southeast-1.maas.aliyuncs.com"
        }
    }
}

public struct FunASRConnectionRoute: Equatable, Sendable {
    public let endpoint: URL
    public let workspaceHeaderValue: String

    public static func resolve(
        region: FunASRServiceRegion,
        workspaceInput: String
    ) -> FunASRConnectionRoute? {
        guard let workspaceID = BailianWorkspaceInput.normalizedID(from: workspaceInput) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(workspaceID).\(region.workspaceHostSuffix)"
        components.path = "/api-ws/v1/inference"
        guard let endpoint = components.url else { return nil }

        return FunASRConnectionRoute(
            endpoint: endpoint,
            workspaceHeaderValue: workspaceID
        )
    }
}
