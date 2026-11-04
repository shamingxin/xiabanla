import Foundation
import ServiceManagement

/// 开机自动启动管理，封装 macOS 13+ 的 SMAppService
struct LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    return
                }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("设置开机自启失败: \(error.localizedDescription)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
