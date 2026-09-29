import Foundation

enum AppState { case locked, working, warned, snoozed, manualBreak }

final class SessionManager {
    static let shared = SessionManager()
    private init() {}

    var onTick: ((TimeInterval, AppState) -> Void)?

    private(set) var state: AppState = .locked
    private(set) var elapsed: TimeInterval = 0
    private(set) var sessionStart: Date?
    private(set) var lockDate: Date?
    private var lastLockDate: Date = .distantPast
    private var lastUnlockDate: Date = .distantPast
    private var tickTimer: Timer?
    private var warningTimer: Timer?
    private var snoozeTimer: Timer?
    private var midnightTimer: Timer?
    private(set) var warningsFired: Int = 0

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

    func startManualBreak() {
        guard state != .locked, state != .manualBreak else { return }
        cancelWarningTimer()
        cancelSnoozeTimer()
        midnightTimer?.invalidate(); midnightTimer = nil
        if let start = sessionStart {
            StatsStore.shared.recordWorkSession(start: start, end: Date())
        }
        sessionStart = nil
        elapsed = 0
        lockDate = Date()
        transition(to: .manualBreak)
        startTicking()
        scheduleMidnightTimer()
    }

    func endManualBreak() {
        guard state == .manualBreak else { return }
        if let lock = lockDate {
            let now = Date()
            let duration = now.timeIntervalSince(lock)
            let threshold = SettingsManager.shared.endOfDayThresholdMinutes
            if threshold == 0 || duration < TimeInterval(threshold * 60) {
                StatsStore.shared.recordBreakSession(start: lock, end: now)
            }
        }
        lockDate = nil
        sessionStart = Date()
        elapsed = 0
        warningsFired = 0
        transition(to: .working)
        startTicking()
        scheduleMidnightTimer()
    }

    func handleUnlock() {
        guard !isDebounced(date: &lastUnlockDate) else { return }
        if let lock = lockDate {
            let now = Date()
            let duration = now.timeIntervalSince(lock)
            let threshold = SettingsManager.shared.endOfDayThresholdMinutes
            if threshold == 0 || duration < TimeInterval(threshold * 60) {
                StatsStore.shared.recordBreakSession(start: lock, end: now)
            }
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
        guard !isDebounced(date: &lastLockDate) else { return }
        stopTicking()
        cancelWarningTimer()
        cancelSnoozeTimer()
        midnightTimer?.invalidate()
        midnightTimer = nil
        if state != .manualBreak, let start = sessionStart {
            StatsStore.shared.recordWorkSession(start: start, end: Date())
        }
        sessionStart = nil
        if state != .manualBreak { lockDate = Date() }
        transition(to: .locked)
    }

    func snooze() {
        guard state == .warned else { return }
        guard warningsFired < SettingsManager.shared.maxWarnings else { return }
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

    func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        let cal = Calendar.current
        guard let midnight = cal.nextDate(after: Date(),
                                          matching: DateComponents(hour: 0, minute: 0, second: 0),
                                          matchingPolicy: .nextTime) else { return }
        let interval = midnight.timeIntervalSinceNow
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.handleMidnightCrossing()
        }
    }

    private func handleMidnightCrossing() {
        guard state != .locked, let start = sessionStart else { return }
        StatsStore.shared.recordWorkSession(start: start, end: Date())
        sessionStart = Date()
        scheduleMidnightTimer()
    }

    private func transition(to newState: AppState) {
        state = newState
        onTick?(elapsed, state)
    }

    private func isDebounced(date: inout Date) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(date) > 1.5 else { return true }
        date = now
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
        StatsView.shared?.refresh()
    }

    private func checkThresholds() {
        let threshold = TimeInterval(SettingsManager.shared.workThresholdMinutes * 60)
        if state == .working && elapsed >= threshold {
            transition(to: .warned)
            warningsFired = 0
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
