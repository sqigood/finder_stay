import AppKit
import FinderSessionRestoreCore

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 58)
    private let recorder: FinderSessionRecorder
    private let restorer: FinderSessionRestorer
    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    private let permissionService: PermissionService
    private let scheduler: SchedulerService
    private var settingsWindowController: SettingsWindowController?

    init(
        recorder: FinderSessionRecorder,
        restorer: FinderSessionRestorer,
        sessionStore: SessionStore,
        settingsStore: SettingsStore,
        permissionService: PermissionService,
        scheduler: SchedulerService
    ) {
        self.recorder = recorder
        self.restorer = restorer
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.scheduler = scheduler
        super.init()
        configureStatusItem()
        rebuildMenu(status: nil)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = "FSR"
            button.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Finder Session Restore")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
    }

    private func rebuildMenu(status: String?) {
        let menu = NSMenu()

        if let status {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(.separator())
        }

        menu.addItem("Save Current Finder State", action: #selector(saveCurrentState), keyEquivalent: "s", target: self)
        menu.addItem("Restore Last Finder State", action: #selector(restoreLastState), keyEquivalent: "r", target: self)
        menu.addItem(.separator())
        menu.addItem("Settings", action: #selector(openSettings), keyEquivalent: ",", target: self)
        menu.addItem(.separator())
        menu.addItem("Quit", action: #selector(quit), keyEquivalent: "q", target: self)

        statusItem.menu = menu
    }

    @objc private func saveCurrentState() {
        rebuildMenu(status: "Saving Finder state...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.recorder.recordNow()
                DispatchQueue.main.async {
                    Self.clearLastError()
                    self.rebuildMenu(status: "Saved \(snapshot.windows.count) Finder window\(snapshot.windows.count == 1 ? "" : "s").")
                    self.playCompletionSound()
                }
            } catch FinderAutomationError.finderNotRunning {
                DispatchQueue.main.async {
                    self.rebuildMenu(status: "Finder is not running.")
                }
            } catch {
                DispatchQueue.main.async {
                    Self.writeLastError(error)
                    self.rebuildMenu(status: "Save failed: \(Self.shortErrorMessage(error))")
                }
            }
        }
    }

    @objc private func restoreLastState() {
        rebuildMenu(status: "Restoring Finder state...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.restorer.restoreLast()
            try? self.sessionStore.saveRestoreReport(report)
            DispatchQueue.main.async {
                self.rebuildMenu(status: report.summary)
                self.playCompletionSound()
                if report.hasWarnings {
                    self.showRestoreWarnings(report)
                }
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                sessionStore: sessionStore,
                permissionService: permissionService,
                scheduler: scheduler
            )
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showRestoreWarnings(_ report: RestoreReport) {
        let alert = NSAlert()
        alert.messageText = report.summary
        alert.informativeText = report.warnings.prefix(5).map { $0.message }.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func playCompletionSound() {
        guard settingsStore.load().soundEffectsEnabled else {
            return
        }
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private static func shortErrorMessage(_ error: Error) -> String {
        let message = (error as NSError).localizedDescription
        if message.count <= 72 {
            return message
        }
        return String(message.prefix(69)) + "..."
    }

    private static func writeLastError(_ error: Error) {
        let nsError = error as NSError
        let directory = SessionStore.defaultBaseDirectory()
        let body = """
        \(Date())
        Domain: \(nsError.domain)
        Code: \(nsError.code)
        Description: \(nsError.localizedDescription)
        Failure reason: \(nsError.localizedFailureReason ?? "None")
        Recovery suggestion: \(nsError.localizedRecoverySuggestion ?? "None")
        User info: \(nsError.userInfo)
        """
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: directory.appendingPathComponent("last-error.txt"), atomically: true, encoding: .utf8)
    }

    private static func clearLastError() {
        let url = SessionStore.defaultBaseDirectory().appendingPathComponent("last-error.txt")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private extension NSMenu {
    func addItem(_ title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        addItem(item)
    }
}
