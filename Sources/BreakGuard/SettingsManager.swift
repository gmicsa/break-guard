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
            "endOfDayThresholdMinutes": 240,
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
    // Breaks longer than this are treated as end-of-day gaps, not recorded. 0 = disabled.
    var endOfDayThresholdMinutes: Int {
        get { defaults.integer(forKey: "endOfDayThresholdMinutes") }
        set { defaults.set(newValue, forKey: "endOfDayThresholdMinutes") }
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
