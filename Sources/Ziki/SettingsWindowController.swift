import AppKit
import Combine
import ZikiAppCore
import SwiftUI

@MainActor
final class SettingsWindowController:
    NSWindowController,
    NSWindowDelegate,
    SettingsWindowPresenting
{
    private var selectionSubscription: AnyCancellable?

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
        window.title = "Ziki — 开始"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(ZikiTheme.paper)
        window.setContentSize(NSSize(width: 900, height: 650))
        window.contentMinSize = NSSize(width: 800, height: 580)
        window.setFrameAutosaveName("ZikiSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        selectionSubscription = model.settingsNavigation.$selection.sink { [weak window] pane in
            window?.title = "Ziki — \((pane ?? .start).rawValue)"
        }
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
