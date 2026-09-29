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
