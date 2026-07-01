import XCTest
@testable import FinderSessionRestoreCore

final class FinderSessionRestoreCoreTests: XCTestCase {
    func testJSONEncodingAndDecoding() throws {
        let snapshot = sampleSnapshot()
        let data = try JSONCoding.encoder.encode(snapshot)
        let decoded = try JSONCoding.decoder.decode(FinderSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testSessionStoreAtomicWritesAndHistoryPruning() throws {
        let directory = temporaryDirectory()
        let store = SessionStore(baseDirectory: directory)

        try store.save(sampleSnapshot(createdAt: Date(timeIntervalSince1970: 1)), historyCount: 1)
        try store.save(sampleSnapshot(createdAt: Date(timeIntervalSince1970: 2)), historyCount: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.latestSessionURL.path))
        let latest = try store.loadLatest()
        XCTAssertEqual(latest.createdAt, Date(timeIntervalSince1970: 2))

        let history = try FileManager.default.contentsOfDirectory(at: store.historyDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(history.count, 1)
    }

    func testSettingsStoreDefaults() {
        let store = SettingsStore(baseDirectory: temporaryDirectory())
        let settings = store.load()

        XCTAssertFalse(settings.autoSaveEnabled)
        XCTAssertEqual(settings.recordingIntervalSeconds, 300)
        XCTAssertEqual(settings.restoreMode, .mergeWithCurrentWindows)
        XCTAssertEqual(settings.networkReconnectTimeoutSeconds, 20)
        XCTAssertEqual(settings.historyCount, 10)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.soundEffectsEnabled)
    }

    func testTargetLocationClassification() {
        XCTAssertEqual(TargetLocation.classify(url: URL(fileURLWithPath: "/Users/example/Desktop")).kind, .local)
        XCTAssertEqual(TargetLocation.classify(url: URL(fileURLWithPath: "/Volumes/Share")).kind, .mountedVolume)
        XCTAssertEqual(TargetLocation.classify(url: URL(string: "smb://server/share")).kind, .network)
        XCTAssertEqual(TargetLocation.classify(url: URL(string: "https://example.com/folder")).kind, .remote)
        XCTAssertEqual(TargetLocation.classify(url: nil, path: "").kind, .unknown)
        XCTAssertFalse(TargetLocation.classify(url: nil, path: "").hasConcreteTarget)
    }

    func testNetworkPreflightUsesMocks() {
        let reachable = MockReachability(reachableDescriptions: ["/Users/example/Desktop"])
        let service = NetworkConnectionService(
            reachabilityChecker: reachable,
            mounter: MockMounter(),
            sleeper: { _ in }
        )

        let local = TargetLocation.classify(url: URL(fileURLWithPath: "/Users/example/Desktop"))
        let result = service.preflight(local, timeout: 0.01)

        XCTAssertTrue(result.isReachable)
        XCTAssertNil(result.warning)
    }

    func testNetworkPreflightWarnsForFailedNetworkMount() {
        let mounter = MockMounter()
        let service = NetworkConnectionService(
            reachabilityChecker: MockReachability(reachableDescriptions: []),
            mounter: mounter,
            sleeper: { _ in }
        )

        let network = TargetLocation.classify(url: URL(string: "smb://server/share"))
        let result = service.preflight(network, timeout: 0.01)

        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.warning?.code, .networkReconnectFailed)
        XCTAssertEqual(mounter.mountedURLs, [URL(string: "smb://server/share")!])
    }

    func testRestoreReportWarningAggregation() {
        var report = RestoreReport()
        report.addWarning(RestoreWarning(code: .targetUnavailable, message: "Saved target no longer exists."))
        report.addWarning(RestoreWarning(code: .spaceRestoreUnavailable, message: "Space restore is unavailable."))

        XCTAssertTrue(report.hasWarnings)
        XCTAssertEqual(report.warnings.count, 2)
        XCTAssertEqual(report.summary, "Restore completed with 2 warnings.")
    }

    func testSessionStorePersistsLatestRestoreReport() throws {
        let store = SessionStore(baseDirectory: temporaryDirectory())
        var report = RestoreReport(startedAt: Date(timeIntervalSince1970: 10))
        report.addWarning(RestoreWarning(code: .spaceRestoreUnavailable, message: "Skipped another Desktop."))
        report.finishedAt = Date(timeIntervalSince1970: 11)

        try store.saveRestoreReport(report)

        let data = try Data(contentsOf: store.latestRestoreReportURL)
        let decoded = try JSONCoding.decoder.decode(RestoreReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }

    func testRestoreSkipsUnsupportedSpaceWithoutClosingCurrentWindows() throws {
        let directory = temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("SavedTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let target = TargetLocation.classify(url: targetDirectory)
        let window = FinderWindowSnapshot(
            id: "other-space",
            title: "SavedTarget",
            bounds: WindowBounds(x: 30, y: 40, width: 600, height: 500),
            display: nil,
            space: SpaceSnapshot(
                id: "2",
                index: nil,
                rawWorkspaceValue: "2",
                restoreSupported: false,
                warning: "This Finder window was saved on another Desktop."
            ),
            target: target,
            tabs: [FinderTabSnapshot(location: target)],
            activeTabIndex: 0
        )

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: [window]),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in }),
            spaceService: MockSpaceService()
        )

        let report = restorer.restoreLast()

        XCTAssertTrue(automation.restoredWindows.isEmpty)
        XCTAssertEqual(report.warnings.map(\.code), [.spaceRestoreUnavailable])
        XCTAssertEqual(report.restoredWindowCount, 0)
    }

    func testRestoreSkipsFallbackSnapshotWithoutRealDesktopIdentity() throws {
        let directory = temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("FinderRestoreCaseB", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let target = TargetLocation.classify(url: targetDirectory)
        let window = FinderWindowSnapshot(
            id: "front-window",
            title: "FinderRestoreCaseB",
            bounds: WindowBounds(x: 820, y: 180, width: 600, height: 520),
            display: nil,
            space: SpaceSnapshot(
                id: "current-space",
                index: nil,
                rawWorkspaceValue: "finder-front-window-fallback",
                restoreSupported: true,
                warning: "Current Desktop window list was unavailable; only the front Finder window was saved."
            ),
            target: target,
            tabs: [FinderTabSnapshot(location: target)],
            activeTabIndex: 0
        )

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: [window]),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in })
        )

        let report = restorer.restoreLast()

        XCTAssertTrue(automation.restoredWindows.isEmpty)
        XCTAssertEqual(report.warnings.map(\.code), [.spaceRestoreUnavailable])
        XCTAssertEqual(report.restoredWindowCount, 0)
    }

    func testRestoreSkipsSingleWindowSnapshotWithoutRealDesktopIdentity() throws {
        let directory = temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("SingleWindow", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let target = TargetLocation.classify(url: targetDirectory)
        let window = FinderWindowSnapshot(
            id: "single",
            title: "SingleWindow",
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600),
            display: nil,
            space: SpaceSnapshot(id: "current-space", index: nil, rawWorkspaceValue: "system-events-visible", restoreSupported: true),
            target: target,
            tabs: [FinderTabSnapshot(location: target)],
            activeTabIndex: 0
        )

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: [window]),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in })
        )

        let report = restorer.restoreLast()

        XCTAssertTrue(automation.restoredWindows.isEmpty)
        XCTAssertEqual(report.warnings.map(\.code), [.spaceRestoreUnavailable])
        XCTAssertEqual(report.restoredWindowCount, 0)
    }

    func testRestoreAllowsWindowWithRealDesktopIdentity() throws {
        let directory = temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("RealDesktopWindow", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let target = TargetLocation.classify(url: targetDirectory)
        let window = FinderWindowSnapshot(
            id: "real-space",
            title: "RealDesktopWindow",
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600),
            display: nil,
            space: SpaceSnapshot(id: "4", index: nil, rawWorkspaceValue: "4", restoreSupported: true),
            target: target,
            tabs: [FinderTabSnapshot(location: target)],
            activeTabIndex: 0
        )

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: [window]),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in })
        )

        let report = restorer.restoreLast()

        XCTAssertEqual(automation.restoredWindows.map(\.title), ["RealDesktopWindow"])
        XCTAssertEqual(report.restoredWindowCount, 1)
    }

    func testRestoreGroupsWindowsBySavedDesktopAndReturnsToOriginalDesktop() throws {
        let directory = temporaryDirectory()
        let targets = ["Space4A", "Space4B", "Space1A"].map {
            directory.appendingPathComponent($0, isDirectory: true)
        }
        for target in targets {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }

        let windows = [
            testWindow(title: "Space4A", target: targets[0], spaceID: "4"),
            testWindow(title: "Space4B", target: targets[1], spaceID: "4"),
            testWindow(title: "Space1A", target: targets[2], spaceID: "1")
        ]

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: windows),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let spaceService = MockSpaceService(currentSpaceID: 9)
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in }),
            spaceService: spaceService
        )

        let report = restorer.restoreLast()

        XCTAssertEqual(automation.restoredWindows.map(\.title), ["Space4A", "Space4B", "Space1A"])
        XCTAssertEqual(spaceService.switchCalls, [4, 1, 9])
        XCTAssertEqual(report.restoredWindowCount, 3)
        XCTAssertFalse(report.hasWarnings)
    }

    func testRestoreSkipsWindowWithoutConcreteTargetWithoutBlankWarning() throws {
        let directory = temporaryDirectory()
        let emptyTarget = TargetLocation.classify(url: nil, path: "")
        let window = FinderWindowSnapshot(
            id: "empty-target",
            title: "Finder Window Without Target",
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600),
            display: nil,
            space: SpaceSnapshot(id: "4", index: nil, rawWorkspaceValue: "4", restoreSupported: true),
            target: emptyTarget,
            tabs: [FinderTabSnapshot(location: emptyTarget)],
            activeTabIndex: 0
        )

        let sessionStore = SessionStore(baseDirectory: directory)
        try sessionStore.save(
            FinderSessionSnapshot(appVersion: "0.1.0", windows: [window]),
            historyCount: 1
        )

        let automation = MockFinderAutomationService()
        let restorer = FinderSessionRestorer(
            automationService: automation,
            sessionStore: sessionStore,
            settingsStore: SettingsStore(baseDirectory: directory),
            permissionService: PermissionService(runner: MockAppleScriptRunner(output: "1")),
            networkService: NetworkConnectionService(sleeper: { _ in }),
            spaceService: MockSpaceService()
        )

        let report = restorer.restoreLast()

        XCTAssertTrue(automation.restoredWindows.isEmpty)
        XCTAssertEqual(report.restoredWindowCount, 0)
        XCTAssertEqual(report.warnings.map(\.code), [.targetUnavailable])
        XCTAssertEqual(report.warnings.first?.targetDescription, "Finder Window Without Target")
    }

    private func sampleSnapshot(createdAt: Date = Date(timeIntervalSince1970: 0)) -> FinderSessionSnapshot {
        let location = TargetLocation.classify(url: URL(fileURLWithPath: "/Users/example/Desktop"))
        let window = FinderWindowSnapshot(
            id: "1",
            title: "Desktop",
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600),
            display: DisplaySnapshot(id: "display-1", name: "Built-in Display"),
            space: SpaceSnapshot(id: "space-1", index: 1, rawWorkspaceValue: "1"),
            target: location,
            tabs: [FinderTabSnapshot(location: location)],
            activeTabIndex: 0
        )
        return FinderSessionSnapshot(appVersion: "0.1.0", createdAt: createdAt, windows: [window])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func testWindow(title: String, target targetURL: URL, spaceID: String) -> FinderWindowSnapshot {
        let target = TargetLocation.classify(url: targetURL)
        return FinderWindowSnapshot(
            id: title,
            title: title,
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600),
            display: nil,
            space: SpaceSnapshot(id: spaceID, index: nil, rawWorkspaceValue: spaceID, restoreSupported: true),
            target: target,
            tabs: [FinderTabSnapshot(location: target)],
            activeTabIndex: 0
        )
    }
}

private final class MockReachability: LocationReachabilityChecking {
    private let reachableDescriptions: Set<String>

    init(reachableDescriptions: Set<String>) {
        self.reachableDescriptions = reachableDescriptions
    }

    func isReachable(_ location: TargetLocation) -> Bool {
        if let path = location.path {
            return reachableDescriptions.contains(path)
        }
        if let url = location.url {
            return reachableDescriptions.contains(url.absoluteString)
        }
        return false
    }
}

private final class MockMounter: NetworkMounting {
    private(set) var mountedURLs: [URL] = []

    func attemptMount(_ url: URL) {
        mountedURLs.append(url)
    }
}

private final class MockAppleScriptRunner: AppleScriptRunning {
    private let output: String

    init(output: String) {
        self.output = output
    }

    func run(_ source: String) throws -> String {
        output
    }
}

private final class MockFinderAutomationService: FinderAutomationServicing {
    private(set) var restoredWindows: [FinderWindowSnapshot] = []

    func isFinderRunning() -> Bool {
        true
    }

    func captureFinderWindows(appVersion: String) throws -> [FinderWindowSnapshot] {
        []
    }

    func savedWindowAlreadyOpen(_ window: FinderWindowSnapshot) -> Bool {
        false
    }

    func restoreWindow(_ window: FinderWindowSnapshot, report: inout RestoreReport) throws {
        restoredWindows.append(window)
        report.restoredWindowCount += 1
    }
}

private final class MockSpaceService: SpaceServicing {
    private let current: UInt64?
    private(set) var switchCalls: [UInt64] = []

    init(currentSpaceID: UInt64? = nil) {
        self.current = currentSpaceID
    }

    func captureSpace(forWindowID id: String?, title: String?, bounds: WindowBounds) -> SpaceSnapshot {
        SpaceSnapshot(id: "4", index: nil, rawWorkspaceValue: "4", restoreSupported: true)
    }

    func prepareRestore(to space: SpaceSnapshot?, report: inout RestoreReport) -> Bool {
        guard let rawWorkspaceValue = space?.rawWorkspaceValue,
              let spaceID = UInt64(rawWorkspaceValue) else {
            return false
        }
        return switchToSpace(spaceID)
    }

    func currentSpaceID() -> UInt64? {
        current
    }

    func switchToSpace(_ spaceID: UInt64) -> Bool {
        switchCalls.append(spaceID)
        return true
    }
}
