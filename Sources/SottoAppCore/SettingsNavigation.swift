import Combine
import Foundation
import SottoCore

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case start = "开始"
    case history = "历史"
    case speech = "语音"
    case providers = "百炼"
    case privacy = "隐私"
    case about = "关于"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .start: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .speech: "waveform"
        case .providers: "server.rack"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

@MainActor
public final class SettingsNavigationState: ObservableObject {
    @Published public var selection: SettingsPane?

    public init(selection: SettingsPane? = .start) {
        self.selection = selection
    }
}

@MainActor
public protocol SettingsWindowPresenting: AnyObject {
    func show()
}

@MainActor
public protocol DictationHistoryPurging: AnyObject {
    @discardableResult
    func purgeExpired() -> Bool
}

extension DictationHistoryStore: DictationHistoryPurging {}

@MainActor
public final class SettingsNavigationCoordinator {
    public let state: SettingsNavigationState
    private let historyPurger: (any DictationHistoryPurging)?
    private weak var presenter: (any SettingsWindowPresenting)?

    public init(
        state: SettingsNavigationState,
        historyPurger: (any DictationHistoryPurging)? = nil
    ) {
        self.state = state
        self.historyPurger = historyPurger
    }

    public func attach(_ presenter: any SettingsWindowPresenting) {
        self.presenter = presenter
    }

    public func openSettings() {
        presenter?.show()
    }

    public func openHistory() {
        historyPurger?.purgeExpired()
        state.selection = .history
        presenter?.show()
    }
}
