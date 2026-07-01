import AppKit
import FinderSessionRestoreCore

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let sessionStore: SessionStore
    private let permissionService: PermissionService
    private let scheduler: SchedulerService

    private let autoSaveCheckbox = NSButton(checkboxWithTitle: "Enable automatic save", target: nil, action: nil)
    private let intervalField = NSTextField()
    private let soundCheckbox = NSButton(checkboxWithTitle: "Play completion sound", target: nil, action: nil)
    private let timeoutField = NSTextField()
    private let historyField = NSTextField()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let lastSavedLabel = NSTextField(labelWithString: "")

    init(
        settingsStore: SettingsStore,
        sessionStore: SessionStore,
        permissionService: PermissionService,
        scheduler: SchedulerService
    ) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.permissionService = permissionService
        self.scheduler = scheduler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Finder Session Restore Settings"
        window.center()
        super.init(window: window)
        buildContent()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        loadSettings()
        super.showWindow(sender)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22)
        ])

        autoSaveCheckbox.target = self
        autoSaveCheckbox.action = #selector(autoSaveToggled)
        stack.addArrangedSubview(settingBlock(
            title: "Automatic Save",
            detail: "Off by default. When enabled, the app saves Finder sessions on the interval below.",
            controls: [autoSaveCheckbox, compactRow(control: intervalField, suffix: "seconds")]
        ))

        stack.addArrangedSubview(settingBlock(
            title: "Completion Sound",
            detail: "Plays after manual save and restore complete.",
            controls: [soundCheckbox]
        ))

        stack.addArrangedSubview(settingBlock(
            title: "Restore Safety",
            detail: "Network timeout is used only for saved network or mounted-volume targets.",
            controls: [compactRow(control: timeoutField, suffix: "seconds")]
        ))

        stack.addArrangedSubview(settingBlock(
            title: "History",
            detail: "Number of saved snapshots to keep in the local app data folder.",
            controls: [compactRow(control: historyField, suffix: "snapshots")]
        ))

        stack.addArrangedSubview(settingBlock(
            title: "Launch",
            detail: "Controls whether the utility starts when you sign in.",
            controls: [launchAtLoginCheckbox]
        ))

        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 4
        stack.addArrangedSubview(settingBlock(
            title: "Permissions",
            detail: "Finder control, window position reading, and Desktop-safe restore depend on these macOS permissions.",
            controls: [permissionLabel]
        ))

        lastSavedLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(lastSavedLabel)

        let utilityRow = NSStackView()
        utilityRow.orientation = .horizontal
        utilityRow.spacing = 8
        utilityRow.addArrangedSubview(NSButton(title: "Open Data Folder", target: self, action: #selector(openDataFolder)))
        utilityRow.addArrangedSubview(NSButton(title: "Request Accessibility", target: self, action: #selector(requestAccessibility)))
        utilityRow.addArrangedSubview(NSButton(title: "Request Screen Recording", target: self, action: #selector(requestScreenRecording)))
        stack.addArrangedSubview(utilityRow)

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.addArrangedSubview(NSButton(title: "Reset Saved Sessions", target: self, action: #selector(resetSavedSessions)))
        bottomRow.addArrangedSubview(NSButton(title: "Save Settings", target: self, action: #selector(saveSettings)))
        stack.addArrangedSubview(bottomRow)
    }

    private func settingBlock(title: String, detail: String, controls: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(titleLabel)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 500).isActive = true
        stack.addArrangedSubview(detailLabel)

        for control in controls {
            stack.addArrangedSubview(control)
        }

        return stack
    }

    private func compactRow(control: NSView, suffix: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        control.widthAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(control)
        let suffixLabel = NSTextField(labelWithString: suffix)
        suffixLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(suffixLabel)
        return stack
    }

    private func loadSettings() {
        let settings = settingsStore.load()
        autoSaveCheckbox.state = settings.autoSaveEnabled ? .on : .off
        intervalField.stringValue = String(Int(settings.recordingIntervalSeconds))
        intervalField.isEnabled = settings.autoSaveEnabled
        soundCheckbox.state = settings.soundEffectsEnabled ? .on : .off
        timeoutField.stringValue = String(Int(settings.networkReconnectTimeoutSeconds))
        historyField.stringValue = String(settings.historyCount)
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off

        let permissions = permissionService.currentStatus()
        permissionLabel.stringValue = [
            permissions.automationAllowed ? "Automation: Granted" : "Automation: Required for Finder control",
            permissions.accessibilityAllowed ? "Accessibility: Granted" : "Accessibility: Required for window positions",
            permissions.screenRecordingLikelyAllowed ? "Screen Recording: Window metadata available" : "Screen Recording: Required for Desktop-safe restore"
        ].joined(separator: "\n")

        if let date = sessionStore.latestSavedDate() {
            lastSavedLabel.stringValue = "Last saved: \(date.formatted(date: .abbreviated, time: .standard))"
        } else {
            lastSavedLabel.stringValue = "Last saved: Never"
        }
    }

    @objc private func autoSaveToggled() {
        intervalField.isEnabled = autoSaveCheckbox.state == .on
    }

    @objc private func saveSettings() {
        let settings = AppSettings(
            autoSaveEnabled: autoSaveCheckbox.state == .on,
            recordingIntervalSeconds: TimeInterval(Int(intervalField.stringValue) ?? 300),
            restoreMode: .mergeWithCurrentWindows,
            networkReconnectTimeoutSeconds: TimeInterval(Int(timeoutField.stringValue) ?? 20),
            historyCount: Int(historyField.stringValue) ?? 10,
            launchAtLogin: launchAtLoginCheckbox.state == .on,
            soundEffectsEnabled: soundCheckbox.state == .on
        )
        try? settingsStore.save(settings)
        scheduler.start()
        loadSettings()
    }

    @objc private func openDataFolder() {
        try? FileManager.default.createDirectory(at: sessionStore.baseDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(sessionStore.baseDirectory)
    }

    @objc private func resetSavedSessions() {
        try? sessionStore.reset()
        loadSettings()
    }

    @objc private func requestAccessibility() {
        permissionService.requestAccessibilityPrompt()
        loadSettings()
    }

    @objc private func requestScreenRecording() {
        permissionService.requestScreenRecordingPrompt()
        loadSettings()
    }
}
