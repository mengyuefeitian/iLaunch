import Darwin
import Foundation

/// Status of a privacy permission that has no public query API.
enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied(message: String)
    /// The probe could not reach a verdict (no usable candidate, timeout, or
    /// a non-TCC errno). Never treated as "denied".
    case unknown
}

/// Detects the "App Management" TCC grant by probing the real resource.
///
/// There is no public API for this permission, so the probe opens another
/// app's `Contents/Info.plist` with `O_WRONLY` (never `O_TRUNC`/`O_CREAT`, and
/// it is closed immediately, so nothing is modified). With the grant the open
/// succeeds; without it TCC rejects the open with `EPERM`. Every other errno
/// (`EACCES`, `EROFS`, `ENOENT`, ...) is a POSIX/filesystem problem, not a
/// TCC verdict, and yields `.unknown`. Candidates are pre-filtered to bundles
/// the current user could write anyway, so a plain permission failure is not
/// mistaken for a TCC denial.
struct AppManagementPermissionChecker: Sendable {
    /// Deep link to Settings > Privacy & Security > App Management.
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
    )!

    static let maxCandidates = 3

    /// The three side effects, injectable so the errno mapping and candidate
    /// filtering are testable without touching real apps.
    struct Environment: Sendable {
        /// Full paths of the entries directly inside /Applications.
        var applicationBundlePaths: @Sendable () -> [String]
        /// Whether this bundle is a safe, POSIX-writable probe target.
        var isEligibleCandidate: @Sendable (String) -> Bool
        /// Opens the file write-only and closes it again. 0 on success, else errno.
        var openForWrite: @Sendable (String) -> Int32

        static let live = Environment(
            applicationBundlePaths: {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
                return names.sorted().map { "/Applications/\($0)" }
            },
            isEligibleCandidate: { bundlePath in
                var linkInfo = stat()
                guard lstat(bundlePath, &linkInfo) == 0, (linkInfo.st_mode & S_IFMT) == S_IFDIR else { return false }
                let plist = infoPlistPath(forBundle: bundlePath)
                var info = stat()
                guard lstat(plist, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
                guard info.st_uid == getuid(), access(plist, W_OK) == 0 else { return false }
                var fs = statfs()
                guard statfs(plist, &fs) == 0, (fs.f_flags & UInt32(MNT_RDONLY)) == 0 else { return false }
                return true
            },
            openForWrite: { path in
                let fd = open(path, O_WRONLY)
                if fd >= 0 {
                    close(fd)
                    return 0
                }
                return errno
            }
        )
    }

    var environment: Environment = .live
    var excludedBundlePath: String = Bundle.main.bundlePath

    static func infoPlistPath(forBundle bundlePath: String) -> String {
        bundlePath + "/Contents/Info.plist"
    }

    /// Blocking probe. Call off the main thread.
    func check() -> PermissionStatus {
        let candidates = environment.applicationBundlePaths()
            .filter { $0.hasSuffix(".app") && $0 != excludedBundlePath }
            .filter(environment.isEligibleCandidate)
            .prefix(Self.maxCandidates)

        guard !candidates.isEmpty else {
            DiagLog.write("appManagement probe: no eligible candidate -> unknown")
            return .unknown
        }
        for bundle in candidates {
            let plist = Self.infoPlistPath(forBundle: bundle)
            let code = environment.openForWrite(plist)
            DiagLog.write("appManagement probe: candidate=\(bundle) errno=\(code)")
            switch code {
            case 0:
                return .granted
            case EPERM:
                return .denied(message: "open(O_WRONLY) on \(plist) failed with EPERM")
            default:
                continue
            }
        }
        return .unknown
    }

    /// Runs the probe on a background queue and gives up after `timeout`
    /// seconds, reporting `.unknown` (e.g. a system prompt blocking the open).
    func check(timeout: TimeInterval) async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                once.resume(with: check())
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.resume(with: .unknown) {
                    DiagLog.write("appManagement probe: timed out after \(timeout)s -> unknown")
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
