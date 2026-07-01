import Foundation

public final class FinderSessionRestorer {
    private let automationService: FinderAutomationServicing
    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    private let permissionService: PermissionService
    private let networkService: NetworkConnectionService
    private let spaceService: SpaceServicing

    public init(
        automationService: FinderAutomationServicing,
        sessionStore: SessionStore,
        settingsStore: SettingsStore,
        permissionService: PermissionService,
        networkService: NetworkConnectionService,
        spaceService: SpaceServicing = SpaceService()
    ) {
        self.automationService = automationService
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.networkService = networkService
        self.spaceService = spaceService
    }

    public func restoreLast() -> RestoreReport {
        var report = RestoreReport()
        let settings = settingsStore.load()

        let snapshot: FinderSessionSnapshot
        do {
            snapshot = try sessionStore.loadLatest()
        } catch DecodingError.dataCorrupted {
            report.addWarning(RestoreWarning(code: .corruptedSnapshot, message: "Saved session JSON is corrupted."))
            report.finishedAt = Date()
            return report
        } catch {
            report.addWarning(RestoreWarning(code: .noSavedSession, message: "No saved Finder session is available."))
            report.finishedAt = Date()
            return report
        }

        let permissionStatus = permissionService.currentStatus()
        permissionStatus.missingWarnings.forEach { report.addWarning($0) }
        if !permissionStatus.automationAllowed {
            report.finishedAt = Date()
            return report
        }
        let allTargets = snapshot.windows.flatMap { window in
            ([window.target] + window.tabs.map(\.location)).filter(\.hasConcreteTarget)
        }

        var preflightResults: [TargetLocation: NetworkConnectionResult] = [:]
        for target in allTargets {
            let result = networkService.preflight(target, timeout: settings.networkReconnectTimeoutSeconds)
            preflightResults[target] = result
            if let warning = result.warning {
                report.addWarning(warning)
            }
        }

        var restorableWindows: [FinderWindowSnapshot] = []
        for window in snapshot.windows {
            if let warning = unsafeSpaceRestoreWarning(for: window) {
                report.addWarning(warning)
                continue
            }

            if let space = window.space, !space.restoreSupported {
                report.addWarning(RestoreWarning(
                    code: .spaceRestoreUnavailable,
                    message: space.warning ?? "This Finder window cannot be safely restored to its saved Space.",
                    targetDescription: window.title ?? window.target.path ?? window.target.url?.absoluteString
                ))
                continue
            }

            if automationService.savedWindowAlreadyOpen(window) {
                continue
            }

            guard window.target.hasConcreteTarget else {
                report.addWarning(RestoreWarning(
                    code: .targetUnavailable,
                    message: "Saved Finder window has no restorable target.",
                    targetDescription: window.title ?? "Untitled Finder window"
                ))
                continue
            }

            guard preflightResults[window.target]?.isReachable ?? true else {
                continue
            }

            var restorableWindow = window
            restorableWindow.tabs = window.tabs.filter { tab in
                tab.location.hasConcreteTarget && (preflightResults[tab.location]?.isReachable ?? true)
            }
            if restorableWindow.tabs.isEmpty {
                restorableWindow.tabs = [FinderTabSnapshot(location: restorableWindow.target)]
            }
            if let activeIndex = restorableWindow.activeTabIndex, activeIndex >= restorableWindow.tabs.count {
                restorableWindow.activeTabIndex = 0
            }

            restorableWindows.append(restorableWindow)
        }

        let originalSpaceID = spaceService.currentSpaceID()
        defer {
            if let originalSpaceID {
                _ = spaceService.switchToSpace(originalSpaceID)
            }
        }

        for group in groupedBySavedSpace(restorableWindows) {
            guard let firstWindow = group.windows.first,
                  spaceService.prepareRestore(to: firstWindow.space, report: &report) else {
                continue
            }

            for restorableWindow in group.windows {
                do {
                    try automationService.restoreWindow(restorableWindow, report: &report)
                } catch {
                    report.addWarning(RestoreWarning(
                        code: .finderAutomationFailed,
                        message: "Finder automation failed while restoring a saved window.",
                        targetDescription: restorableWindow.target.url?.absoluteString ?? restorableWindow.target.path
                    ))
                }
            }
        }

        report.finishedAt = Date()
        return report
    }

    private func unsafeSpaceRestoreWarning(for window: FinderWindowSnapshot) -> RestoreWarning? {
        guard let space = window.space else {
            return RestoreWarning(
                code: .spaceRestoreUnavailable,
                message: "Saved window has no Desktop identity, so it was not restored to avoid opening it on the wrong Desktop.",
                targetDescription: window.title ?? window.target.path ?? window.target.url?.absoluteString
            )
        }

        guard let rawWorkspaceValue = space.rawWorkspaceValue,
              rawWorkspaceValue.allSatisfy({ $0.isNumber }) else {
            return RestoreWarning(
                code: .spaceRestoreUnavailable,
                message: "Saved window does not include a real Desktop identity, so it was not restored to avoid opening it on the wrong Desktop.",
                targetDescription: window.title ?? window.target.path ?? window.target.url?.absoluteString
            )
        }

        return nil
    }

    private func groupedBySavedSpace(_ windows: [FinderWindowSnapshot]) -> [SpaceRestoreGroup] {
        var orderedSpaceIDs: [UInt64] = []
        var groups: [UInt64: [FinderWindowSnapshot]] = [:]

        for window in windows {
            guard let rawWorkspaceValue = window.space?.rawWorkspaceValue,
                  let spaceID = UInt64(rawWorkspaceValue) else {
                continue
            }

            if groups[spaceID] == nil {
                orderedSpaceIDs.append(spaceID)
                groups[spaceID] = []
            }
            groups[spaceID]?.append(window)
        }

        return orderedSpaceIDs.compactMap { spaceID in
            guard let windows = groups[spaceID] else {
                return nil
            }
            return SpaceRestoreGroup(spaceID: spaceID, windows: windows)
        }
    }
}

private struct SpaceRestoreGroup {
    var spaceID: UInt64
    var windows: [FinderWindowSnapshot]
}
