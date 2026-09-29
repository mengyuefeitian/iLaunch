import Foundation
import Testing
@testable import iLaunch

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

private func cocoaError(_ code: Int) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code)
}

@Suite struct AppTrashServiceTests {
    @Test func scriptEscapesQuotesAndBackslashes() {
        let script = SystemAppTrasher.finderTrashScript(path: "/Applications/A \"B\" \\C.app")
        #expect(script == "tell application \"Finder\" to delete (POSIX file \"/Applications/A \\\"B\\\" \\\\C.app\" as alias)")
    }

    @Test func scriptKeepsCJKCharactersIntact() {
        let script = SystemAppTrasher.finderTrashScript(path: "/Applications/汽水音乐.app")
        #expect(script.contains("POSIX file \"/Applications/汽水音乐.app\""))
    }

    @Test func permissionErrorsNeedElevation() {
        #expect(SystemAppTrasher.needsElevation(cocoaError(NSFileWriteNoPermissionError)))
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        #expect(SystemAppTrasher.needsElevation(posix))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        #expect(SystemAppTrasher.needsElevation(wrapped))
        #expect(!SystemAppTrasher.needsElevation(cocoaError(NSFileNoSuchFileError)))
    }

    @Test func successfulRecycleNeverCallsFallback() async {
        let calls = Counter()
        let trasher = SystemAppTrasher(recycle: { _ in nil }, finderFallback: { _ in calls.increment(); return true })
        #expect(await trasher.moveToTrash(path: "/x.app"))
        #expect(calls.count == 0)
    }

    @Test func permissionFailureFallsBackAndReturnsFallbackResult() async {
        let calls = Counter()
        let ok = SystemAppTrasher(recycle: { _ in cocoaError(513) }, finderFallback: { _ in calls.increment(); return true })
        #expect(await ok.moveToTrash(path: "/x.app"))
        let failing = SystemAppTrasher(recycle: { _ in cocoaError(513) }, finderFallback: { _ in calls.increment(); return false })
        #expect(await failing.moveToTrash(path: "/x.app") == false)
        #expect(calls.count == 2)
    }

    @Test func nonPermissionFailureDoesNotFallBack() async {
        let calls = Counter()
        let trasher = SystemAppTrasher(recycle: { _ in cocoaError(NSFileNoSuchFileError) }, finderFallback: { _ in calls.increment(); return true })
        #expect(await trasher.moveToTrash(path: "/x.app") == false)
        #expect(calls.count == 0)
    }
}
