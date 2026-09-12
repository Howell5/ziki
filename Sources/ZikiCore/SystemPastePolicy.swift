public enum SystemPasteCopyReason: Equatable, Sendable {
    case ownAppFocused
    case secureField
}

public enum SystemPasteDecision: Equatable, Sendable {
    case paste
    case copyOnly(reason: SystemPasteCopyReason)
}

public enum SystemPastePolicy {
    public static func decide(
        focusedProcessIsOwnApp: Bool?,
        focusedElementIsSecure: Bool
    ) -> SystemPasteDecision {
        if focusedElementIsSecure {
            return .copyOnly(reason: .secureField)
        }
        if focusedProcessIsOwnApp == true {
            return .copyOnly(reason: .ownAppFocused)
        }
        return .paste
    }
}
