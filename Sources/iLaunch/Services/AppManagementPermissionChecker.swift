import Darwin
import Foundation

/// Status of a privacy permission that has no public query API.
enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied(message: String)
    /// No verdict (not determined, symbol unavailable, or timeout). Never
    /// treated as "denied".
    case unknown
}

/// Detects the "App Management" TCC grant via the private
/// `TCCAccessPreflight(service, options)` call from TCC.framework.
///
/// It evaluates the calling process's identity and returns 0 = granted,
/// 1 = denied, 2 = not determined. A file-open probe was tried first but is
/// unreliable: unsigned target bundles are not protected, so it always
/// "succeeds". The symbol is resolved at runtime with dlopen/dlsym (no link
/// dependency); if it is unavailable the status is `.unknown`. iLaunch is
/// distributed via Sparkle/DMG, so private API is acceptable here.
struct AppManagementPermissionChecker: Sendable {
    /// Deep link to Settings > Privacy & Security > App Management.
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
    )!

    static let tccFrameworkPath = "/System/Library/PrivateFrameworks/TCC.framework/TCC"
    static let tccService = "kTCCServiceSystemPolicyAppBundles"

    /// Raw preflight result, or nil when the symbol could not be resolved.
    typealias Preflight = @Sendable () -> Int32?

    var preflight: Preflight = AppManagementPermissionChecker.livePreflight

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32

    static func livePreflight() -> Int32? {
        guard let handle = dlopen(tccFrameworkPath, RTLD_LAZY),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        let function = unsafeBitCast(symbol, to: PreflightFunction.self)
        return function(tccService as CFString, nil)
    }

    static func status(forPreflightResult result: Int32?) -> PermissionStatus {
        switch result {
        case 0: .granted
        case 1: .denied(message: "TCCAccessPreflight(\(tccService)) returned 1 (denied)")
        default: .unknown
        }
    }

    /// Blocking check. Call off the main thread.
    func check() -> PermissionStatus {
        let result = preflight()
        let status = Self.status(forPreflightResult: result)
        DiagLog.write("appManagement preflight: result=\(result.map(String.init) ?? "nil") -> \(status)")
        return status
    }

    /// Runs the check on a background queue and gives up after `timeout`
    /// seconds, reporting `.unknown` (e.g. a blocked call).
    func check(timeout: TimeInterval) async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                once.resume(with: check())
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.resume(with: .unknown) {
                    DiagLog.write("appManagement preflight: timed out after \(timeout)s -> unknown")
                }
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PermissionStatus, Never>?

    init(_ continuation: CheckedContinuation<PermissionStatus, Never>) {
        self.continuation = continuation
    }

    /// Returns true if this call was the one that resumed.
    @discardableResult
    func resume(with status: PermissionStatus) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return false }
        pending.resume(returning: status)
        return true
    }
}
