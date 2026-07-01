import AppKit
import FinderSessionRestoreCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var scheduler: SchedulerService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let sessionStore = SessionStore()
        let settingsStore = SettingsStore()
        let permissionService = PermissionService()
        let spaceService = SpaceService()
        let automationService = FinderAutomationService(spaceService: spaceService)
        let networkService = NetworkConnectionService()
        let recorder = FinderSessionRecorder(
            automationService: automationService,
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            appVersion: appVersion
        )
        let restorer = FinderSessionRestorer(
            automationService: automationService,
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            permissionService: permissionService,
            networkService: networkService,
            spaceService: spaceService
        )

        menuBarController = MenuBarController(
            recorder: recorder,
            restorer: restorer,
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            permissionService: permissionService
        )

        scheduler = SchedulerService(settingsStore: settingsStore, recorder: recorder)
        scheduler?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
    }
}
