import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var notificationWarningItem: NSMenuItem?
    private var snoozeItem: NSMenuItem?
    private var snoozeSeparator: NSMenuItem?
    private var manualBreakItem: NSMenuItem?
    private var workingForItem: NSMenuItem?

    // Hover tracking for the tooltip
    private var hoverPollTimer: Timer?
    private var isHoveringButton = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        NotificationManager.shared.setup()
        NotificationManager.shared.sessionManager = SessionManager.shared
        NotificationManager.shared.checkNotificationPermission()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌿 --:--"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        buildMenu()
        statusItem.menu = menu

        setupHoverTracking()

        SessionManager.shared.onTick = { [weak self] elapsed, state in
            DispatchQueue.main.async { self?.updateLabel(elapsed: elapsed, state: state) }
        }

        registerObservers()

        // Start in working state immediately — if the screen is already unlocked
        // the first lock event (if it comes quickly) will correctly transition to .locked.
        SessionManager.shared.startWorking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.flushSession()
    }

    // MARK: - Notification permission warning

    func setNotificationWarningVisible(_ visible: Bool) {
        notificationWarningItem?.isHidden = !visible
    }

    // MARK: - Label update

    private func updateLabel(elapsed: TimeInterval, state: AppState) {
        let (text, color) = formatLabel(elapsed: elapsed, state: state)
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        ])
    }

    private func formatLabel(elapsed: TimeInterval, state: AppState) -> (String, NSColor) {
        switch state {
        case .locked:      return ("🌿 --:--", NSColor.secondaryLabelColor)
        case .working:     return ("💻 \(formatTime(elapsed))", NSColor.systemGreen)
        case .warned:      return ("⏰ \(formatTime(elapsed))", NSColor.systemRed)
        case .snoozed:     return ("💤 \(formatTime(elapsed))", NSColor.systemOrange)
        case .manualBreak: return ("🌿 \(formatTime(elapsed))", NSColor.secondaryLabelColor)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - Hover tracking (tooltip)

    private func setupHoverTracking() {
        hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
        RunLoop.main.add(hoverPollTimer!, forMode: .common)
    }

    private func checkHover() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            if isHoveringButton {
                isHoveringButton = false
                TooltipWindowController.shared.hide()
            }
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let buttonFrameOnScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        let nowHovering = buttonFrameOnScreen.contains(mouseLocation)

        if nowHovering && !isHoveringButton {
            isHoveringButton = true
            TooltipWindowController.shared.show(relativeTo: button)
        } else if !nowHovering && isHoveringButton {
            isHoveringButton = false
            TooltipWindowController.shared.hide()
        }
    }

    // MARK: - Lock / Unlock observers

    private func registerObservers() {
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(self, selector: #selector(handleLock),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        wsNC.addObserver(self, selector: #selector(handleUnlock),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleLock),
            name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(handleUnlock),
            name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)
        dnc.addObserver(self, selector: #selector(handleLock),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(handleUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func handleLock() {
        SessionManager.shared.handleLock()
        DispatchQueue.main.async { [weak self] in
            self?.updateLabel(elapsed: 0, state: .locked)
        }
    }

    @objc private func handleUnlock() {
        SessionManager.shared.handleUnlock()
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self

        // Take a break / Back to work toggle (first action)
        let breakItem = NSMenuItem(title: "Take a break", action: #selector(toggleManualBreak), keyEquivalent: "")
        breakItem.target = self
        manualBreakItem = breakItem
        menu.addItem(breakItem)
        menu.addItem(.separator())

        // ⚠️ Notifications disabled (hidden by default)
        let warnItem = NSMenuItem(title: "⚠️ Notifications disabled", action: #selector(openNotificationSettings), keyEquivalent: "")
        warnItem.target = self
        warnItem.isHidden = true
        notificationWarningItem = warnItem
        menu.addItem(warnItem)
        menu.addItem(.separator())

        // Working for X
        let workingItem = NSMenuItem(title: "Working for 0:00", action: nil, keyEquivalent: "")
        workingItem.isEnabled = false
        workingForItem = workingItem
        menu.addItem(workingItem)
        menu.addItem(.separator())

        // Snooze
        let snooze = NSMenuItem(title: "Snooze \(SettingsManager.shared.snoozeDurationMinutes) min", action: #selector(snoozeAction), keyEquivalent: "")
        snooze.target = self
        snooze.isEnabled = false
        snooze.isHidden = true
        snoozeItem = snooze
        menu.addItem(snooze)
        let snoozeSep = NSMenuItem.separator()
        snoozeSep.isHidden = true
        snoozeSeparator = snoozeSep
        menu.addItem(snoozeSep)

        // View Stats
        let statsItem = NSMenuItem(title: "View Stats...", action: #selector(openStats), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)
        menu.addItem(.separator())

        // Settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = buildSettingsMenu()
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit BreakGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        TooltipWindowController.shared.hide()
        updateDynamicMenuItems()
    }

    private func updateDynamicMenuItems() {
        let state = SessionManager.shared.state
        let elapsed = SessionManager.shared.elapsed

        // Working for label
        switch state {
        case .locked:
            workingForItem?.title = "Screen locked"
        case .manualBreak:
            workingForItem?.title = "On break for \(formatTime(elapsed))"
        case .working, .warned, .snoozed:
            workingForItem?.title = "Working for \(formatTime(elapsed))"
        }

        // Snooze availability
        let canSnooze = state == .warned && SessionManager.shared.warningsFired < SettingsManager.shared.maxWarnings
        snoozeItem?.isHidden = !canSnooze
        snoozeItem?.isEnabled = canSnooze
        snoozeSeparator?.isHidden = !canSnooze
        snoozeItem?.title = "Snooze \(SettingsManager.shared.snoozeDurationMinutes) min"

        // Manual break toggle
        switch state {
        case .locked:
            manualBreakItem?.title = "Take a break"
            manualBreakItem?.isEnabled = false
        case .manualBreak:
            manualBreakItem?.title = "Back to work"
            manualBreakItem?.isEnabled = true
        default:
            manualBreakItem?.title = "Take a break"
            manualBreakItem?.isEnabled = true
        }
    }

    // MARK: - Settings menu

    private func buildSettingsMenu() -> NSMenu {
        let s = NSMenu()

        // Work threshold
        let threshItem = NSMenuItem(title: "Work threshold", action: nil, keyEquivalent: "")
        threshItem.submenu = buildThresholdMenu()
        s.addItem(threshItem)

        // Warning interval
        let intervalItem = NSMenuItem(title: "Warning interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = buildIntervalMenu()
        s.addItem(intervalItem)

        // Warning count
        let countItem = NSMenuItem(title: "Warning count", action: nil, keyEquivalent: "")
        countItem.submenu = buildWarningCountMenu()
        s.addItem(countItem)

        // Snooze duration
        let snoozeItem = NSMenuItem(title: "Snooze duration", action: nil, keyEquivalent: "")
        snoozeItem.submenu = buildSnoozeDurationMenu()
        s.addItem(snoozeItem)

        // End-of-day threshold
        let eodItem = NSMenuItem(title: "End-of-day threshold", action: nil, keyEquivalent: "")
        eodItem.submenu = buildEndOfDayThresholdMenu()
        s.addItem(eodItem)

        s.addItem(.separator())

        // Sounds
        let soundsItem = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        soundsItem.submenu = buildSoundsMenu()
        s.addItem(soundsItem)

        s.addItem(.separator())

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SettingsManager.shared.launchAtLogin ? .on : .off
        s.addItem(loginItem)

        return s
    }

    private func buildThresholdMenu() -> NSMenu {
        let m = NSMenu()
        let current = SettingsManager.shared.workThresholdMinutes
        for val in [45, 60, 90] {
            let item = NSMenuItem(title: "\(val) minutes", action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.target = self; item.tag = val
            item.state = current == val ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(customThreshold), keyEquivalent: "")
        custom.target = self
        if ![45, 60, 90].contains(current) { custom.state = .on }
        m.addItem(custom)
        return m
    }

    private func buildIntervalMenu() -> NSMenu {
        let m = NSMenu()
        let current = SettingsManager.shared.warningIntervalMinutes
        for val in [5, 10] {
            let item = NSMenuItem(title: "\(val) minutes", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self; item.tag = val
            item.state = current == val ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(customInterval), keyEquivalent: "")
        custom.target = self
        if ![5, 10].contains(current) { custom.state = .on }
        m.addItem(custom)
        return m
    }

    private func buildWarningCountMenu() -> NSMenu {
        let m = NSMenu()
        let current = SettingsManager.shared.maxWarnings
        let options: [(Int, String)] = [(4, "4  (20 min)"), (6, "6  (30 min)"), (12, "12 (60 min)")]
        for (val, label) in options {
            let item = NSMenuItem(title: label, action: #selector(setWarningCount(_:)), keyEquivalent: "")
            item.target = self; item.tag = val
            item.state = current == val ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(customWarningCount), keyEquivalent: "")
        custom.target = self
        if ![4, 6, 12].contains(current) { custom.state = .on }
        m.addItem(custom)
        return m
    }

    private func buildSnoozeDurationMenu() -> NSMenu {
        let m = NSMenu()
        let current = SettingsManager.shared.snoozeDurationMinutes
        for val in [5, 10, 15] {
            let item = NSMenuItem(title: "\(val) minutes", action: #selector(setSnoozeDuration(_:)), keyEquivalent: "")
            item.target = self; item.tag = val
            item.state = current == val ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(customSnoozeDuration), keyEquivalent: "")
        custom.target = self
        if ![5, 10, 15].contains(current) { custom.state = .on }
        m.addItem(custom)
        return m
    }

    private func buildEndOfDayThresholdMenu() -> NSMenu {
        let m = NSMenu()
        let current = SettingsManager.shared.endOfDayThresholdMinutes
        let options: [(Int, String)] = [
            (0,   "Disabled"),
            (120, "2 hours"),
            (180, "3 hours"),
            (240, "4 hours"),
            (360, "6 hours")
        ]
        for (val, label) in options {
            let item = NSMenuItem(title: label, action: #selector(setEndOfDayThreshold(_:)), keyEquivalent: "")
            item.target = self; item.tag = val
            item.state = current == val ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(customEndOfDayThreshold), keyEquivalent: "")
        custom.target = self
        if ![0, 120, 180, 240, 360].contains(current) { custom.state = .on }
        m.addItem(custom)
        return m
    }

    private let availableSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
                                   "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                                   "Submarine", "Tink"]

    private func buildSoundsMenu() -> NSMenu {
        let m = NSMenu()

        // Enable sounds toggle
        let toggle = NSMenuItem(title: "Enable sounds", action: #selector(toggleSound), keyEquivalent: "")
        toggle.target = self
        toggle.state = SettingsManager.shared.soundEnabled ? .on : .off
        m.addItem(toggle)
        m.addItem(.separator())

        // Info sound submenu
        let infoItem = NSMenuItem(title: "Info sound", action: nil, keyEquivalent: "")
        infoItem.submenu = buildSoundPickerMenu(current: SettingsManager.shared.infoSoundName, action: #selector(setInfoSound(_:)))
        m.addItem(infoItem)

        // Warning sound submenu
        let warnItem = NSMenuItem(title: "Warning sound", action: nil, keyEquivalent: "")
        warnItem.submenu = buildSoundPickerMenu(current: SettingsManager.shared.warningSoundName, action: #selector(setWarningSound(_:)))
        m.addItem(warnItem)

        return m
    }

    private func buildSoundPickerMenu(current: String, action: Selector) -> NSMenu {
        let m = NSMenu()
        for name in availableSounds {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = current == name ? .on : .off
            m.addItem(item)
        }
        return m
    }

    // MARK: - Actions

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func snoozeAction() {
        SessionManager.shared.snooze()
    }

    @objc private func toggleManualBreak() {
        if SessionManager.shared.state == .manualBreak {
            SessionManager.shared.endManualBreak()
        } else {
            SessionManager.shared.startManualBreak()
        }
    }

    @objc private func openStats() {
        StatsWindowController.showWindow()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = !SettingsManager.shared.launchAtLogin
        SettingsManager.shared.launchAtLogin = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        SettingsManager.shared.soundEnabled = !SettingsManager.shared.soundEnabled
        sender.state = SettingsManager.shared.soundEnabled ? .on : .off
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        SettingsManager.shared.workThresholdMinutes = sender.tag
        rebuildSettingsSubmenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        SettingsManager.shared.warningIntervalMinutes = sender.tag
        rebuildSettingsSubmenu()
    }

    @objc private func setWarningCount(_ sender: NSMenuItem) {
        SettingsManager.shared.maxWarnings = sender.tag
        rebuildSettingsSubmenu()
    }

    @objc private func setSnoozeDuration(_ sender: NSMenuItem) {
        SettingsManager.shared.snoozeDurationMinutes = sender.tag
        rebuildSettingsSubmenu()
    }

    @objc private func setInfoSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        SettingsManager.shared.infoSoundName = name
        SoundManager.shared.play(name)
        rebuildSettingsSubmenu()
    }

    @objc private func setWarningSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        SettingsManager.shared.warningSoundName = name
        SoundManager.shared.play(name)
        rebuildSettingsSubmenu()
    }

    @objc private func customThreshold() {
        promptCustom(title: "Work threshold (1–480 min)",
                     current: SettingsManager.shared.workThresholdMinutes,
                     min: 1, max: 480) {
            SettingsManager.shared.workThresholdMinutes = $0
            self.rebuildSettingsSubmenu()
        }
    }

    @objc private func customInterval() {
        let maxVal = min(120, SettingsManager.shared.workThresholdMinutes)
        promptCustom(title: "Warning interval (1–\(maxVal) min)",
                     current: SettingsManager.shared.warningIntervalMinutes,
                     min: 1, max: maxVal) {
            SettingsManager.shared.warningIntervalMinutes = $0
            self.rebuildSettingsSubmenu()
        }
    }

    @objc private func customWarningCount() {
        promptCustom(title: "Warning count (1–99)",
                     current: SettingsManager.shared.maxWarnings,
                     min: 1, max: 99) {
            SettingsManager.shared.maxWarnings = $0
            self.rebuildSettingsSubmenu()
        }
    }

    @objc private func customSnoozeDuration() {
        promptCustom(title: "Snooze duration (1–120 min)",
                     current: SettingsManager.shared.snoozeDurationMinutes,
                     min: 1, max: 120) {
            SettingsManager.shared.snoozeDurationMinutes = $0
            self.rebuildSettingsSubmenu()
        }
    }

    @objc private func setEndOfDayThreshold(_ sender: NSMenuItem) {
        SettingsManager.shared.endOfDayThresholdMinutes = sender.tag
        rebuildSettingsSubmenu()
    }

    @objc private func customEndOfDayThreshold() {
        promptCustom(title: "End-of-day threshold (0=disabled, 1–720 min)",
                     current: SettingsManager.shared.endOfDayThresholdMinutes,
                     min: 0, max: 720) {
            SettingsManager.shared.endOfDayThresholdMinutes = $0
            self.rebuildSettingsSubmenu()
        }
    }

    private func promptCustom(title: String, current: Int, min minVal: Int, max maxVal: Int, completion: @escaping (Int) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        tf.stringValue = "\(current)"
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        if alert.runModal() == .alertFirstButtonReturn {
            if let val = Int(tf.stringValue), val >= minVal && val <= maxVal {
                completion(val)
            } else {
                let err = NSAlert()
                err.messageText = "Invalid value"
                err.informativeText = "Please enter a whole number between \(minVal) and \(maxVal)."
                err.runModal()
            }
        }
    }

    private func rebuildSettingsSubmenu() {
        guard let settingsIdx = menu.items.firstIndex(where: { $0.title == "Settings" }) else { return }
        menu.items[settingsIdx].submenu = buildSettingsMenu()
    }
}
