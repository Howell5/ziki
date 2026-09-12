import AppKit
import ApplicationServices
import CoreGraphics
import ZikiAppCore
import ZikiCore

@MainActor
final class TextInsertionService: DictationTextInserting {
    func insert(_ text: String) async -> TextInsertionOutcome {
        guard AXIsProcessTrusted() else {
            copyOnly(text)
            return .copied(
                ClipboardRecoveryCopy.message(reason: "需要辅助功能权限")
            )
        }

        let focusedElement = systemFocusedElement()
        let focusedProcessIsOwnApp = focusedElement.flatMap {
            processID(of: $0).map {
                $0 == ProcessInfo.processInfo.processIdentifier
            }
        }
        let focusedElementIsSecure =
            focusedElement.flatMap {
                attribute("AXSubrole", from: $0) as? String
            } == "AXSecureTextField"

        switch SystemPastePolicy.decide(
            focusedProcessIsOwnApp: focusedProcessIsOwnApp,
            focusedElementIsSecure: focusedElementIsSecure
        ) {
        case .paste:
            break
        case let .copyOnly(reason):
            copyOnly(text)
            switch reason {
            case .ownAppFocused:
                return .copied(
                    ClipboardRecoveryCopy.message(
                        reason: "Ziki 当前正在接收输入"
                    )
                )
            case .secureField:
                return .copied(
                    ClipboardRecoveryCopy.message(
                        reason: "安全输入框不会自动写入"
                    )
                )
            }
        }

        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            copyOnly(text)
            return .copied(
                ClipboardRecoveryCopy.message(reason: "需要自动粘贴权限")
            )
        }

        // Do not resolve or classify a target here. macOS routes Command-V
        // to the control that owns the keyboard focus at this exact moment.
        copyOnly(text)
        guard postCommandV() else {
            return .copied(
                ClipboardRecoveryCopy.message(reason: "无法发送粘贴按键")
            )
        }
        return .inserted
    }

    private func systemFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let value = attribute(
            "AXFocusedUIElement",
            from: systemWide
        ),
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else {
            return nil
        }
        return processID
    }

    private func attribute(
        _ name: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func copyOnly(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0x09,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0x09,
                  keyDown: false
              )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
