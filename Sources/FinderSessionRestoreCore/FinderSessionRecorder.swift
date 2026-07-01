import Foundation

public final class FinderSessionRecorder {
    private let automationService: FinderAutomationServicing
    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    private let appVersion: String

    public init(
        automationService: FinderAutomationServicing,
        sessionStore: SessionStore,
        settingsStore: SettingsStore,
        appVersion: String
    ) {
        self.automationService = automationService
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.appVersion = appVersion
    }

    public func recordNow() throws -> FinderSessionSnapshot {
        guard automationService.isFinderRunning() else {
            throw FinderAutomationError.finderNotRunning
        }

        let windows = try automationService.captureFinderWindows(appVersion: appVersion)
        let snapshot = FinderSessionSnapshot(appVersion: appVersion, windows: windows)
        try sessionStore.save(snapshot, historyCount: settingsStore.load().historyCount)
        return snapshot
    }
}
