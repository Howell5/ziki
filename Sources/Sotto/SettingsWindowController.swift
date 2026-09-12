import AppKit
import SottoAppCore
import SwiftUI

@MainActor
final class SettingsWindowController:
    NSWindowController,
    NSWindowDelegate,
    SettingsWindowPresenting
{
    init(model: AppModel) {
        let rootView = SettingsRootView()
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.permissions)
            .environmentObject(model.historyStore)
            .environmentObject(model.settingsNavigation)
            .environmentObject(model.updater)
            .environmentObject(model.outputMute)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Sotto Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 680, height: 500)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
