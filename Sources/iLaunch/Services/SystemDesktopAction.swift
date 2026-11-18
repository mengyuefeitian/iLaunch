import CoreFoundation
import Darwin

/// Sends the same Dock notification used for the system Show Desktop action.
enum SystemDesktopAction {
    @discardableResult
    static func toggle() -> Bool {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            DiagLog.write("show desktop: ApplicationServices unavailable")
            return false
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CoreDockSendNotification") else {
            DiagLog.write("show desktop: CoreDockSendNotification unavailable")
            return false
        }
        typealias SendNotification = @convention(c) (CFString, Int32) -> Int32
        let send = unsafeBitCast(symbol, to: SendNotification.self)
        let status = send("com.apple.showdesktop.awake" as CFString, 0)
        DiagLog.write("show desktop: Dock notification status=\(status)")
        return status == 0
    }
}
