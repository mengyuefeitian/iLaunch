import Foundation
import Testing
@testable import iLaunch

private final class OpenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    func record(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
}

private func makeChecker(
    apps: [String],
    eligible: @escaping @Sendable (String) -> Bool = { _ in true },
    openResults: @escaping @Sendable (String) -> Int32,
    recorder: OpenRecorder = OpenRecorder(),
    excluded: String = "/Applications/iLaunch.app"
) -> AppManagementPermissionChecker {
    AppManagementPermissionChecker(
        environment: .init(
            applicationBundlePaths: { apps },
            isEligibleCandidate: eligible,
            openForWrite: { path in recorder.record(path); return openResults(path) }
        ),
        excludedBundlePath: excluded
    )
}

@Test func openSucceedingMeansGranted() {
    let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in 0 })
    #expect(checker.check() == .granted)
}

@Test func epermMeansDenied() {
    let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in EPERM })
    guard case .denied = checker.check() else {
        Issue.record("expected .denied")
        return
    }
}

@Test func otherErrnosAreUnknownNotDenied() {
    for code in [EACCES, EROFS, ENOENT, EBUSY] {
        let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in code })
        #expect(checker.check() == .unknown, "errno \(code)")
    }
}

@Test func noCandidatesMeansUnknown() {
    let checker = makeChecker(apps: [], openResults: { _ in 0 })
    #expect(checker.check() == .unknown)
}

@Test func probesInfoPlistInsideTheBundle() {
    let recorder = OpenRecorder()
    let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in 0 }, recorder: recorder)
    _ = checker.check()
    #expect(recorder.paths == ["/Applications/Foo.app/Contents/Info.plist"])
}

@Test func skipsOwnBundleNonAppEntriesAndIneligibleCandidates() {
    let recorder = OpenRecorder()
    let checker = makeChecker(
        apps: ["/Applications/iLaunch.app", "/Applications/readme.txt", "/Applications/Root.app", "/Applications/Mine.app"],
        eligible: { $0 != "/Applications/Root.app" },
        openResults: { _ in 0 },
        recorder: recorder
    )
    _ = checker.check()
    #expect(recorder.paths == ["/Applications/Mine.app/Contents/Info.plist"])
}

@Test func triesNextCandidateAfterInconclusiveErrno() {
    let recorder = OpenRecorder()
    let checker = makeChecker(
        apps: ["/Applications/A.app", "/Applications/B.app"],
        openResults: { $0.contains("/A.app/") ? EROFS : EPERM },
        recorder: recorder
    )
    guard case .denied = checker.check() else {
        Issue.record("expected .denied from second candidate")
        return
    }
    #expect(recorder.paths.count == 2)
}

@Test func givesUpAfterMaxCandidates() {
    let recorder = OpenRecorder()
    let apps = (1...10).map { "/Applications/App\($0).app" }
    let checker = makeChecker(apps: apps, openResults: { _ in EACCES }, recorder: recorder)
    #expect(checker.check() == .unknown)
    #expect(recorder.paths.count == AppManagementPermissionChecker.maxCandidates)
}

@Test func timeoutTreatsSlowProbeAsUnknown() async {
    let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in
        Thread.sleep(forTimeInterval: 1.0)
        return 0
    })
    let status = await checker.check(timeout: 0.1)
    #expect(status == .unknown)
}

@Test func asyncCheckReturnsProbeResultWhenFast() async {
    let checker = makeChecker(apps: ["/Applications/Foo.app"], openResults: { _ in 0 })
    #expect(await checker.check(timeout: 2) == .granted)
}

@Test func deepLinkPointsAtAppManagementPane() {
    #expect(AppManagementPermissionChecker.systemSettingsURL.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
}
