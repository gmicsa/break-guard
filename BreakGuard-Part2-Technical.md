# BreakGuard — Technical Specification

---

## 1. Technology Stack

| Constraint | Decision |
|---|---|
| Language | Swift 5.9+ |
| UI framework | AppKit only (`NSStatusBar`, `NSMenu`, `NSPanel`, `NSView`, `NSTableView`) |
| Charts | Custom CoreGraphics drawing — no SwiftCharts, no third-party libs |
| Notifications | `UserNotifications` framework |
| Sound | `NSSound(named:)` — uses built-in macOS system sounds, no file bundling needed |
| Persistence | JSON files in `~/Library/Application Support/BreakGuard/` |
| Minimum macOS | 13.0 Ventura |
| Sandbox | Disabled (`com.apple.security.app-sandbox = false`) — required for `NSWorkspace` and `DistributedNotificationCenter` |
| Distribution | `swift build -c release` — no Xcode project required |

---

## 2. Project Structure

```
BreakGuard/
├── Package.swift
├── Sources/
│   └── BreakGuard/
│       ├── main.swift                  # NSApplication bootstrap, activation policy
│       ├── AppDelegate.swift           # Status bar, menu, workspace observers
│       ├── SessionManager.swift        # Timer, state machine, snooze logic
│       ├── NotificationManager.swift   # UNUserNotificationCenter wrapper
│       ├── SoundManager.swift          # NSSound wrapper
│       ├── StatsStore.swift            # JSON read/write for daily stats
│       ├── SettingsManager.swift       # UserDefaults wrapper for all settings
│       ├── LoginItemManager.swift      # SMAppService launch-at-login wrapper
│       ├── StatsWindowController.swift # NSWindowController for stats popup
│       ├── StatsView.swift             # NSView: today summary + session table + chart
│       └── BarChartView.swift          # NSView: CoreGraphics 7-day bar chart
```

No `Resources/` folder needed — all sounds are system-provided.

---

## 3. Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BreakGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BreakGuard",
            path: "Sources/BreakGuard"
        )
    ]
)
```

---

## 4. main.swift

```swift
import AppKit

// Hide Dock icon — this is a menu bar only app
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

> **Note:** Alternatively, add `<key>LSUIElement</key><true/>` to an `Info.plist`. With `swift run` / SPM there is no automatic plist, so use the programmatic approach above.

---

## 5. State Machine

```
              +-----------------------------------------+
              |                                         |
LOCKED --[unlock]--> WORKING --[threshold reached]--> WARNED
   ^              ^                                     |  ^
   |           [lock]                               [snooze]|
[lock]             |                                    |  |
   |           SNOOZED <-----------------------------------+  |
   |               |                                       |
   |           [snooze expires] -------------------------->+
   |
[any lock event flushes session and goes to LOCKED]
```

| State | Menu bar color | Description |
|---|---|---|
| `locked` | Gray | Screen locked |
| `working` | Green | Timer counting up; no alerts yet |
| `warned` | Red | Past `workThreshold`; repeat warnings firing |
| `snoozed` | Orange | Warning repeat paused; timer still running |

### State transitions

| Event | From | To | Side effects |
|---|---|---|---|
| Unlock | `locked` | `working` | Reset `elapsed = 0`; record break session (lock to now); start tick timer |
| Lock | any | `locked` | Stop tick timer; cancel snooze timer; persist work session; record `lockDate = now` |
| `elapsed >= workThreshold` | `working` | `warned` | Fire info notification; play info sound; set `warningsFired = 0` |
| Warning timer fires | `warned` | `warned` | Fire warning notification; play warning sound; increment `warningsFired`; stop if `warningsFired >= maxWarnings` |
| Snooze | `warned` | `snoozed` | Cancel warning repeat timer; start snooze countdown |
| Snooze expires | `snoozed` | `warned` | Restart warning repeat timer |

> Snooze does NOT freeze `elapsed`. The user is still at their desk. Only the warning repeat timer is paused.
>
> `warningsFired` is NOT reset on snooze/resume. The counter continues from its pre-snooze value. Snooze is disabled (menu item grayed out) once `warningsFired >= maxWarnings`.

---

## 6. SettingsManager

All settings persisted in `UserDefaults(suiteName: "com.breakguard.settings")`.

| Key | Type | Default |
|---|---|---|
| `workThresholdMinutes` | `Int` | `60` |
| `warningIntervalMinutes` | `Int` | `5` |
| `maxWarnings` | `Int` | `6` |
| `snoozeDurationMinutes` | `Int` | `10` |
| `soundEnabled` | `Bool` | `true` |
| `infoSoundName` | `String` | `"Glass"` |
| `warningSoundName` | `String` | `"Sosumi"` |
| `launchAtLogin` | `Bool` | `false` |

```swift
// SettingsManager.swift
import Foundation

final class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults(suiteName: "com.breakguard.settings")!
    private init() { registerDefaults() }

    private func registerDefaults() {
        defaults.register(defaults: [
            "workThresholdMinutes": 60,
            "warningIntervalMinutes": 5,
            "maxWarnings": 6,
            "snoozeDurationMinutes": 10,
            "soundEnabled": true,
            "infoSoundName": "Glass",
            "warningSoundName": "Sosumi",
            "launchAtLogin": false
        ])
    }

    var workThresholdMinutes: Int {
        get { defaults.integer(forKey: "workThresholdMinutes") }
        set { defaults.set(newValue, forKey: "workThresholdMinutes") }
    }
    var warningIntervalMinutes: Int {
        get { defaults.integer(forKey: "warningIntervalMinutes") }
        set { defaults.set(newValue, forKey: "warningIntervalMinutes") }
    }
    var maxWarnings: Int {
        get { defaults.integer(forKey: "maxWarnings") }
        set { defaults.set(newValue, forKey: "maxWarnings") }
    }
    var snoozeDurationMinutes: Int {
        get { defaults.integer(forKey: "snoozeDurationMinutes") }
        set { defaults.set(newValue, forKey: "snoozeDurationMinutes") }
    }
    var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }
    var infoSoundName: String {
        get { defaults.string(forKey: "infoSoundName") ?? "Glass" }
        set { defaults.set(newValue, forKey: "infoSoundName") }
    }
    var warningSoundName: String {
        get { defaults.string(forKey: "warningSoundName") ?? "Sosumi" }
        set { defaults.set(newValue, forKey: "warningSoundName") }
    }
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            LoginItemManager.shared.setEnabled(newValue)
        }
    }
}
```

---

## 7. Lock / Unlock Detection

Use two notification centers together. Both are needed:
- `NSWorkspace` catches screensaver start/stop and fast-user-switching
- `DistributedNotificationCenter` catches `Cmd+Ctrl+Q` lock screen

```swift
func registerObservers() {
    let wsNC = NSWorkspace.shared.notificationCenter
    wsNC.addObserver(self, selector: #selector(handleLock),
        name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    wsNC.addObserver(self, selector: #selector(handleUnlock),
        name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

    let dnc = DistributedNotificationCenter.default()
    // Screensaver start/stop (DistributedNotificationCenter required — NSWorkspace notifications unreliable here)
    dnc.addObserver(self, selector: #selector(handleLock),
        name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
    dnc.addObserver(self, selector: #selector(handleUnlock),
        name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)
    // Cmd+Ctrl+Q lock screen
    dnc.addObserver(self, selector: #selector(handleLock),
        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    dnc.addObserver(self, selector: #selector(handleUnlock),
        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
}
```

### Debounce

Multiple notifications often fire for the same physical event. Debounce with a 1.5-second guard:

```swift
private var lastEventDate: Date = .distantPast

func isDebounced() -> Bool {
    let now = Date()
    guard now.timeIntervalSince(lastEventDate) > 1.5 else { return true }
    lastEventDate = now
    return false
}

@objc func handleLock() {
    guard !isDebounced() else { return }
    sessionManager.handleLock()
}

@objc func handleUnlock() {
    guard !isDebounced() else { return }
    sessionManager.handleUnlock()
}
```

---

## 8. Menu Bar Label

Use `NSStatusItem` with `NSVariableStatusItemLength`. Set `attributedTitle` on every tick (every 60 seconds) via the tick callback.

```swift
func makeAttributedTitle(_ text: String, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .foregroundColor: color,
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    ])
}
```

Use `NSFont.monospacedDigitSystemFont` so the timer doesn't jitter as digit widths change.

---

## 9. Menu Construction

Rebuild via `NSMenuDelegate.menuWillOpen` so dynamic items are always fresh. Custom value input:

```swift
func promptCustomMinutes(title: String, current: Int, completion: @escaping (Int) -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
    tf.stringValue = "\(current)"
    alert.accessoryView = tf
    alert.window.initialFirstResponder = tf
    if alert.runModal() == .alertFirstButtonReturn {
        if let val = Int(tf.stringValue), val > 0 {
            completion(val)
        } else {
            let err = NSAlert()
            err.messageText = "Invalid value"
            err.informativeText = "Please enter a whole number greater than 0."
            err.runModal()
        }
    }
}
```

---

## 10. NotificationManager

```swift
// NotificationManager.swift
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // Weak reference so NotificationManager can call snooze() directly from
    // the notification action handler without a retain cycle.
    weak var sessionManager: SessionManager?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze \(SettingsManager.shared.snoozeDurationMinutes) min",
            options: []
        )
        let warnCategory = UNNotificationCategory(
            identifier: "BREAK_WARN",
            actions: [snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([warnCategory])

        // Request permission (alert only — sound managed manually)
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.updatePermissionWarning(granted: granted) }
        }
    }

    // Called on setup and whenever the app becomes active.
    // Shows/hides the ⚠️ menu item based on current authorization status.
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let denied = settings.authorizationStatus == .denied
                AppDelegate.shared?.setNotificationWarningVisible(denied)
            }
        }
    }

    private func updatePermissionWarning(granted: Bool) {
        AppDelegate.shared?.setNotificationWarningVisible(!granted)
    }

    func sendInfoNotification(elapsedMinutes: Int) {
        send(id: "break_info",
             title: "Time for a break! ☕",
             body: "You've been working for \(elapsedMinutes) minutes. Step away and rest.",
             categoryId: "BREAK_INFO")
        SoundManager.shared.playInfo()
    }

    func sendWarningNotification(elapsedMinutes: Int) {
        send(id: "break_warn_\(Date().timeIntervalSince1970)",
             title: "Still working? 🔴",
             body: "You've been at it for \(elapsedMinutes) minutes. Your body needs a break.",
             categoryId: "BREAK_WARN")
        SoundManager.shared.playWarning()
    }

    func sendSnoozeEndNotification() {
        send(id: "snooze_end",
             title: "Snooze over 🔔",
             body: "Break reminder is back. Consider stepping away now.",
             categoryId: "BREAK_WARN")
        SoundManager.shared.playWarning()
    }

    private func send(id: String, title: String, body: String, categoryId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryId
        content.sound = .none
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "SNOOZE" {
            // Call snooze() directly via the weak sessionManager reference.
            DispatchQueue.main.async { self.sessionManager?.snooze() }
        }
        completionHandler()
    }

    // Always show banners — menu bar app is always "foreground"
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
```

---

## 11. LoginItemManager

Wraps `SMAppService` to register/unregister the app as a login item. Called by `SettingsManager` whenever `launchAtLogin` changes.

```swift
// LoginItemManager.swift
import Foundation
import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()
    private init() {}

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Log failure; UI toggle reverts via SettingsManager on next menu open
            print("LoginItemManager: \(error)")
        }
    }
}
```

> **Note:** `SMAppService` requires macOS 13+, which matches the deployment target.

---

## 13. SoundManager

```swift
// SoundManager.swift
import AppKit

final class SoundManager {
    static let shared = SoundManager()
    private init() {}

    func playInfo()    { play(SettingsManager.shared.infoSoundName) }
    func playWarning() { play(SettingsManager.shared.warningSoundName) }

    func play(_ name: String) {
        guard SettingsManager.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
```

Sound preview in the Settings submenu: the menu item action calls `SoundManager.shared.play(soundName)` directly.

---

## 14. SessionManager

```swift
// SessionManager.swift
import Foundation

enum AppState { case locked, working, warned, snoozed }

final class SessionManager {
    static let shared = SessionManager()
    private init() {}

    var onTick: ((TimeInterval, AppState) -> Void)?

    private(set) var state: AppState = .locked
    private var elapsed: TimeInterval = 0
    private var sessionStart: Date?
    private var lockDate: Date?
    private var lastEventDate: Date = .distantPast
    private var tickTimer: Timer?
    private var warningTimer: Timer?
    private var snoozeTimer: Timer?
    private var warningsFired: Int = 0

    // Called once during applicationDidFinishLaunching to start tracking
    // immediately if the screen is already unlocked at launch.
    // Unlike handleUnlock, this does NOT record a break session for the
    // period before launch (that time is unknown).
    func startWorking() {
        sessionStart = Date()
        elapsed = 0
        warningsFired = 0
        transition(to: .working)
        startTicking()
        scheduleMidnightTimer()
    }

    func handleUnlock() {
        guard !isDebounced() else { return }
        if let lock = lockDate {
            StatsStore.shared.recordBreakSession(start: lock, end: Date())
        }
        lockDate = nil
        sessionStart = Date()
        elapsed = 0
        warningsFired = 0
        transition(to: .working)
        startTicking()
        scheduleMidnightTimer()
    }

    func handleLock() {
        guard !isDebounced() else { return }
        stopTicking()
        cancelWarningTimer()
        cancelSnoozeTimer()
        if let start = sessionStart {
            StatsStore.shared.recordWorkSession(start: start, end: Date())
        }
        sessionStart = nil
        lockDate = Date()
        transition(to: .locked)
    }

    func snooze() {
        guard state == .warned else { return }
        cancelWarningTimer()
        transition(to: .snoozed)
        let duration = TimeInterval(SettingsManager.shared.snoozeDurationMinutes * 60)
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.snoozeExpired()
        }
    }

    func flushSession() {
        guard state != .locked, let start = sessionStart else { return }
        StatsStore.shared.recordWorkSession(start: start, end: Date())
    }

    // Called once on unlock (and on app launch if screen is unlocked).
    // Schedules a one-shot timer to fire at the next midnight boundary.
    // When it fires, the current partial work session is saved and a new
    // session record is started for the new calendar day.
    func scheduleMidnightTimer() {
        let cal = Calendar.current
        guard let midnight = cal.nextDate(after: Date(),
                                          matching: DateComponents(hour: 0, minute: 0, second: 0),
                                          matchingPolicy: .nextTime) else { return }
        let interval = midnight.timeIntervalSinceNow
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.handleMidnightCrossing()
        }
    }

    private func handleMidnightCrossing() {
        guard state != .locked, let start = sessionStart else { return }
        StatsStore.shared.recordWorkSession(start: start, end: Date())
        sessionStart = Date()
        scheduleMidnightTimer()   // schedule for next midnight
    }

    private func transition(to newState: AppState) {
        state = newState
        onTick?(elapsed, state)
    }

    private func isDebounced() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastEventDate) > 1.5 else { return true }
        lastEventDate = now
        return false
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        elapsed += 60
        onTick?(elapsed, state)
        checkThresholds()
        StatsView.shared?.refresh()  // stats window refresh on every tick
    }

    private func checkThresholds() {
        let threshold = TimeInterval(SettingsManager.shared.workThresholdMinutes * 60)
        if state == .working && elapsed >= threshold {
            transition(to: .warned)
            NotificationManager.shared.sendInfoNotification(elapsedMinutes: Int(elapsed / 60))
            startWarningTimer()
        }
    }

    private func startWarningTimer() {
        cancelWarningTimer()
        let interval = TimeInterval(SettingsManager.shared.warningIntervalMinutes * 60)
        warningTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.warningTimerFired()
        }
    }

    private func cancelWarningTimer() { warningTimer?.invalidate(); warningTimer = nil }
    private func cancelSnoozeTimer()  { snoozeTimer?.invalidate();  snoozeTimer = nil }

    private func warningTimerFired() {
        guard state == .warned else { return }
        guard warningsFired < SettingsManager.shared.maxWarnings else {
            cancelWarningTimer(); return
        }
        warningsFired += 1
        NotificationManager.shared.sendWarningNotification(elapsedMinutes: Int(elapsed / 60))
    }

    private func snoozeExpired() {
        transition(to: .warned)
        NotificationManager.shared.sendSnoozeEndNotification()
        startWarningTimer()
    }
}
```

---

## 15. StatsStore & Data Model

### File location

`~/Library/Application Support/BreakGuard/stats-YYYY-MM-DD.json` — one file per calendar day in local timezone.

### JSON schema

```json
{
  "date": "2026-03-20",
  "sessions": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "startedAt": "2026-03-20T08:32:11Z",
      "endedAt": "2026-03-20T10:15:44Z",
      "durationSeconds": 6213,
      "type": "work"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "startedAt": "2026-03-20T10:15:44Z",
      "endedAt": "2026-03-20T10:28:01Z",
      "durationSeconds": 737,
      "type": "break"
    }
  ]
}
```

### Data structures

```swift
struct SessionRecord: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date?      // nil only for the live in-progress session (never persisted as nil); flushed sessions store the quit timestamp
    let durationSeconds: TimeInterval
    let type: SessionType
}

enum SessionType: String, Codable {
    case work = "work"
    case `break` = "break"
}

struct DayFile: Codable {
    let date: String        // "YYYY-MM-DD"
    var sessions: [SessionRecord]
}

struct DaySummary {
    let date: Date
    let totalWorkSeconds: TimeInterval
    let totalBreakSeconds: TimeInterval
    var totalSeconds: TimeInterval { totalWorkSeconds + totalBreakSeconds }
    let sessions: [SessionRecord]
}
```

### StatsStore API

```swift
final class StatsStore {
    static let shared = StatsStore()

    func recordWorkSession(start: Date, end: Date)
    func recordBreakSession(start: Date, end: Date)   // ignores if duration < 5s
    func todaySummary() -> DaySummary
    func lastNDays(_ n: Int) -> [DaySummary]          // sorted ascending, includes today

    // Internal: splits sessions spanning midnight into two records
    private func splitAtMidnight(start: Date, end: Date) -> [(Date, Date, Date)]

    // Internal: load/save with corrupt-file recovery (.bak.json on decode failure)
    private func load(date: Date) -> DayFile
    private func save(_ dayFile: DayFile, date: Date)
}
```

---

## 16. Stats Window

### Window spec

| Property | Value |
|---|---|
| Class | `NSPanel` subclass via `NSWindowController` |
| Style | `.titled + .closable + .fullSizeContentView` |
| Level | `.floating` |
| Size | 680 x 620 pt |
| Title | `"BreakGuard — Session Stats"` |
| Resizable | No |
| Singleton | One instance; `makeKeyAndOrderFront` if already open |

### Layout

```
+------------------------------------------------------------------+
|  BreakGuard -- Session Stats                              [x]    |
+------------------------------------------------------------------+
|                                                                  |
|  TODAY -- Thursday, March 20                   [bold, 15pt]      |
|  +----------------------------------------------------------+    |
|  |  🟢 Total Work    4h 32m     🔵 Total Break    1h 10m   |    |
|  +----------------------------------------------------------+    |
|                                                                  |
|  Session Log                                   [semibold, 13pt]  |
|  +------+------------+------------+----------------------------+ |
|  | Type | Start      | End        | Duration                   | |
|  +------+------------+------------+----------------------------+ |
|  | 🟢   | 08:32      | 10:15      | 1h 43m                     | |
|  | 🔵   | 10:15      | 10:28      | 13m                        | |
|  | 🟢   | 10:28      | 12:44      | 2h 16m                     | |
|  | 🔵   | 12:44      | 13:17      | 33m                        | |
|  | 🟢   | 13:17      | ongoing    | -                          | |
|  +------+------------+------------+----------------------------+ |
|  [NSScrollView wrapping NSTableView, max height 180pt]           |
|                                                                  |
|  Last 7 Days                                   [semibold, 13pt]  |
|  +----------------------------------------------------------+    |
|  |  [BarChartView -- 240pt tall]                            |    |
|  +----------------------------------------------------------+    |
|                                                                  |
+------------------------------------------------------------------+
```

### NSTableView columns

| Column ID | Header | Width | Content |
|---|---|---|---|
| `type` | `Type` | 50pt | Colored circle emoji: 🟢 work, 🔵 break |
| `start` | `Start` | 90pt | `HH:mm` in local time |
| `end` | `End` | 90pt | `HH:mm` or `"ongoing"` if `endedAt == nil` |
| `duration` | `Duration` | 100pt | `Xh Ym` or `Ym` or `"-"` if ongoing |

- No editing
- `usesAlternatingRowBackgroundColors = true`
- Reload data on every `windowWillAppear`

### StatsView data flow

`StatsView` holds a reference to `SessionManager` (injected at construction). On each call to `refresh()` — triggered by every tick — it:

1. Calls `StatsStore.shared.todaySummary()` for completed sessions.
2. Reads `SessionManager.elapsed` and `SessionManager.sessionStart` to construct a synthetic "ongoing" `SessionRecord` (type `.work`, `endedAt = nil`).
3. Merges the synthetic record into the session list for display (appended at the end if state is `.working`, `.warned`, or `.snoozed`).
4. Adds `SessionManager.elapsed` to `totalWorkSeconds` for the Today summary totals.
5. Calls `tableView.reloadData()` and redraws the today summary labels.

`StatsView.shared` is a weak singleton used by `SessionManager.tick()` to call `refresh()` without a strong dependency.

---

## 17. BarChartView

Custom `NSView` subclass. Override `draw(_ dirtyRect: NSRect)` using CoreGraphics. No libraries.

### Drawing rules

- **Background:** `NSColor.windowBackgroundColor`
- **Y-axis:** 40pt left margin; 4 equidistant gridlines; label format `"Xh"`; gridline color `NSColor.separatorColor` at 0.5pt
- **Bar pairs:** work bar (left, `NSColor.systemGreen`) + break bar (right, `NSColor.systemBlue`); 4pt gap within pair; 12pt gap between day groups
- **Bar width:** `(availableWidth - 7 * 12) / 7 / 2`, minimum 6pt
- **Bar height:** proportional; tallest single bar maps to 80% of chart height; minimum 2pt for non-zero values
- **Top label:** `"Xh Ym"` total per day; `NSFont.systemFont(ofSize: 9)`; centered above pair; omit if both zero
- **Bottom label:** `"Mon"` ... `"Today"` for rightmost day; `NSFont.systemFont(ofSize: 10)`
- **Top-only rounded corners:** `NSBezierPath(roundedRect:xRadius:yRadius:)` with the rect extended below the chart area
- **Legend:** bottom-right; green dot + `"Work"`, blue dot + `"Break"`; `NSFont.systemFont(ofSize: 10)`

### Draw order

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    // 1. Fill background
    // 2. Compute layout: margins, bar width, scale factor
    // 3. Draw Y-axis gridlines and labels
    // 4. For each of 7 days:
    //    a. Draw work bar (if > 0)
    //    b. Draw break bar (if > 0)
    //    c. Draw total label above pair
    //    d. Draw day name below pair
    // 5. Draw legend
}
```

Call `needsDisplay = true` each time the stats window opens.

---

## 18. AppDelegate

```swift
// AppDelegate.swift
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var notificationWarningItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        NotificationManager.shared.setup()
        NotificationManager.shared.sessionManager = SessionManager.shared
        NotificationManager.shared.checkNotificationPermission()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "☕ --:--"

        buildMenu()
        statusItem.menu = menu

        SessionManager.shared.onTick = { [weak self] elapsed, state in
            DispatchQueue.main.async { self?.updateLabel(elapsed: elapsed, state: state) }
        }

        registerObservers()

        // Start in working state immediately — if the screen is already unlocked
        // when the app launches we want to begin tracking right away.
        // The first lock event (if the screen was actually locked) will
        // correctly transition to .locked via the debounce guard.
        SessionManager.shared.startWorking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.flushSession()
    }

    // Show or hide the ⚠️ Notifications disabled item at the top of the menu.
    // Tapping it opens System Settings > Notifications.
    func setNotificationWarningVisible(_ visible: Bool) {
        notificationWarningItem?.isHidden = !visible
    }

    private func updateLabel(elapsed: TimeInterval, state: AppState) {
        let (text, color) = formatLabel(elapsed: elapsed, state: state)
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        ])
    }

    private func formatLabel(elapsed: TimeInterval, state: AppState) -> (String, NSColor) {
        switch state {
        case .locked:  return ("☕ --:--", NSColor.secondaryLabelColor)
        case .working: return ("🟢 \(formatTime(elapsed))", NSColor.systemGreen)
        case .warned:  return ("🔴 \(formatTime(elapsed))", NSColor.systemRed)
        case .snoozed: return ("🟠 \(formatTime(elapsed))", NSColor.systemOrange)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        return String(format: "%d:%02d", h, m)  // e.g. "1:05" or "10:30" — no seconds
    }

    @objc func menuWillOpen(_ menu: NSMenu) {
        updateDynamicMenuItems()
    }
}
```

---

## 19. Build & Run

```bash
mkdir -p BreakGuard/Sources/BreakGuard
cd BreakGuard
# Place all source files under Sources/BreakGuard/

swift build -c release
.build/release/BreakGuard
```

### First-run checklist

1. macOS prompts for notification permission — click **Allow**
2. App appears in menu bar only (no Dock icon)
3. Lock (`Cmd+Ctrl+Q`) and unlock to begin first session
4. Stats JSON: `~/Library/Application Support/BreakGuard/`

### Signing for distribution

```bash
codesign --deep --force --sign "-" .build/release/BreakGuard
```

---

## 20. Implementation Order

1. `Package.swift` + `main.swift` — bare status item visible in menu bar
2. `SettingsManager` — UserDefaults wrapper
3. `SessionManager` — state machine + tick timer (no UI yet)
4. `AppDelegate` — workspace observers + label updates + initial working state
5. `StatsStore` — JSON persistence
6. `NotificationManager` + `SoundManager`
7. `LoginItemManager` — `SMAppService` launch-at-login wrapper
8. Menu construction — all items, settings submenus, notification warning item, launch-at-login toggle
9. `StatsWindowController` + `StatsView` — today summary + session table (with SessionManager reference)
10. `BarChartView` — 7-day chart
11. End-to-end test: lock/unlock cycle, check JSON, open Stats window
