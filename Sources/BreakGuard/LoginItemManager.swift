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
            print("LoginItemManager: \(error)")
        }
    }
}
