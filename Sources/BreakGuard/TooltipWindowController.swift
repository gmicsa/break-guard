import AppKit

// MARK: - Tooltip content view

private final class TooltipContentView: NSView {

    private let workIconLabel  = NSTextField(labelWithString: "")
    private let breakIconLabel = NSTextField(labelWithString: "")
    private let workValue      = NSTextField(labelWithString: "")
    private let breakValue     = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        for label in [workIconLabel, breakIconLabel, workValue, breakValue] {
            label.isEditable      = false
            label.isBordered      = false
            label.drawsBackground = false
            label.lineBreakMode   = .byClipping
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(workSeconds: TimeInterval, breakSeconds: TimeInterval, isDark: Bool) {
        layer?.backgroundColor = isDark
            ? NSColor(white: 0.18, alpha: 0.97).cgColor
            : NSColor(white: 0.94, alpha: 0.97).cgColor

        let secondaryColor: NSColor = isDark
            ? NSColor(white: 0.6, alpha: 1)
            : NSColor(white: 0.45, alpha: 1)

        let fontSize: CGFloat = 11
        let regular = NSFont.systemFont(ofSize: fontSize)
        let mono    = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)

        workIconLabel.attributedStringValue  = NSAttributedString(string: "💻  Work today",  attributes: [.font: regular, .foregroundColor: secondaryColor])
        breakIconLabel.attributedStringValue = NSAttributedString(string: "🌿  Break today", attributes: [.font: regular, .foregroundColor: secondaryColor])

        workValue.attributedStringValue  = NSAttributedString(string: formatDuration(workSeconds),  attributes: [.font: mono, .foregroundColor: NSColor.systemBlue])
        breakValue.attributedStringValue = NSAttributedString(string: formatDuration(breakSeconds), attributes: [.font: mono, .foregroundColor: NSColor.systemGreen])

        workValue.alignment  = .right
        breakValue.alignment = .right

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let padX: CGFloat   = 10
        let padY: CGFloat   = 9
        let rowH: CGFloat   = 16
        let gap:  CGFloat   = 5
        let w = bounds.width
        let labelW: CGFloat = 110
        let valueW: CGFloat = w - labelW - padX * 2

        let row1Y = bounds.height - padY - rowH
        let row2Y = row1Y - gap - rowH

        workIconLabel.frame  = NSRect(x: padX, y: row1Y, width: labelW, height: rowH)
        breakIconLabel.frame = NSRect(x: padX, y: row2Y, width: labelW, height: rowH)
        workValue.frame      = NSRect(x: padX + labelW, y: row1Y, width: valueW, height: rowH)
        breakValue.frame     = NSRect(x: padX + labelW, y: row2Y, width: valueW, height: rowH)
    }

    // MARK: - Helpers

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else {
            return String(format: "%dm", m)
        }
    }
}

// MARK: - Controller

final class TooltipWindowController {

    static let shared = TooltipWindowController()
    private init() {}

    private var panel: NSPanel?

    func show(relativeTo button: NSButton) {
        hide()

        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let size = NSSize(width: 190, height: 58)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = TooltipContentView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view

        let summary  = StatsStore.shared.todaySummary()
        let sm       = SessionManager.shared
        let isWorking = sm.state == .working || sm.state == .warned || sm.state == .snoozed
        view.update(workSeconds:  summary.totalWorkSeconds  + (isWorking            ? sm.elapsed : 0),
                    breakSeconds: summary.totalBreakSeconds + (sm.state == .manualBreak ? sm.elapsed : 0),
                    isDark: isDark)

        // Position below the status bar button
        if let buttonWindow = button.window,
           let screen = buttonWindow.screen ?? NSScreen.main {
            let buttonFrame = buttonWindow.convertToScreen(
                button.convert(button.bounds, to: nil)
            )
            var origin = NSPoint(
                x: buttonFrame.midX - size.width / 2,
                y: buttonFrame.minY - size.height - 4
            )
            let screenRight = screen.visibleFrame.maxX
            let screenLeft  = screen.visibleFrame.minX
            if origin.x + size.width > screenRight { origin.x = screenRight - size.width - 4 }
            if origin.x < screenLeft               { origin.x = screenLeft + 4 }
            if origin.y < screen.visibleFrame.minY {
                origin.y = buttonFrame.maxY + NSStatusBar.system.thickness + 4
            }
            panel.setFrameOrigin(origin)
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

