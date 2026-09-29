import AppKit

final class StatsWindowController: NSWindowController {

    private static var _instance: StatsWindowController?

    static func showWindow() {
        if _instance == nil {
            _instance = StatsWindowController()
        }
        _instance?.showAndBringToFront()
    }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "BreakGuard — Session Stats"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()

        let statsView = StatsView(sessionManager: SessionManager.shared)
        statsView.frame = NSRect(x: 0, y: 0, width: 680, height: 620)
        panel.contentView = statsView

        self.init(window: panel)
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func showAndBringToFront() {
        (window?.contentView as? StatsView)?.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func windowWillLoad() {
        super.windowWillLoad()
    }
}
