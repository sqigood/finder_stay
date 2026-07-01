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
    private let tabView = NSTabView()

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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
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

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        contentView.addSubview(tabView)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footer)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(NSButton(title: "Save Settings", target: self, action: #selector(saveSettings)))

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            tabView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        addTab(label: "General", contentView: generalTab())
        addTab(label: "Restore", contentView: restoreTab())
        addTab(label: "Permissions", contentView: permissionsTab())
        addTab(label: "Data", contentView: dataTab())
    }

    private func generalTab() -> NSView {
        autoSaveCheckbox.target = self
        autoSaveCheckbox.action = #selector(autoSaveToggled)

        return tabContent([
            settingSection(
                title: "Automatic Save",
                detail: "Off by default. Turn this on only if you want periodic Finder session snapshots.",
                controls: [autoSaveCheckbox, fieldRow(control: intervalField, suffix: "seconds")]
            ),
            settingSection(
                title: "Completion Sound",
                detail: "Play a short system sound after manual save and restore complete.",
                controls: [soundCheckbox]
            ),
            settingSection(
                title: "Startup",
                detail: "Open the menu bar utility automatically when you sign in.",
                controls: [launchAtLoginCheckbox]
            )
        ])
    }

    private func restoreTab() -> NSView {
        return tabContent([
            settingSection(
                title: "Network Timeout",
                detail: "Used only when restoring saved targets on mounted volumes or network locations.",
                controls: [fieldRow(control: timeoutField, suffix: "seconds")]
            ),
            settingSection(
                title: "Snapshot History",
                detail: "Keeps recent local snapshots so the latest Finder state can be restored safely.",
                controls: [fieldRow(control: historyField, suffix: "snapshots")]
            )
        ])
    }

    private func permissionsTab() -> NSView {
        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 5
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(NSButton(title: "Request Accessibility", target: self, action: #selector(requestAccessibility)))
        buttonRow.addArrangedSubview(NSButton(title: "Request Screen Recording", target: self, action: #selector(requestScreenRecording)))

        return tabContent([
            settingSection(
                title: "macOS Permissions",
                detail: "Finder control, window positions, and Desktop-safe restore depend on these system permissions.",
                controls: [permissionLabel, buttonRow]
            )
        ])
    }

    private func dataTab() -> NSView {
        lastSavedLabel.textColor = .secondaryLabelColor
        lastSavedLabel.lineBreakMode = .byTruncatingMiddle

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(NSButton(title: "Open Data Folder", target: self, action: #selector(openDataFolder)))
        buttonRow.addArrangedSubview(NSButton(title: "Reset Saved Sessions", target: self, action: #selector(resetSavedSessions)))

        return tabContent([
            settingSection(
                title: "Saved Sessions",
                detail: "Local session data is stored in the app support folder on this Mac.",
                controls: [lastSavedLabel, buttonRow]
            )
        ])
    }

    private func addTab(label: String, contentView: NSView) {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = contentView
        tabView.addTabViewItem(item)
    }

    private func tabContent(_ sections: [NSView]) -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        for section in sections {
            stack.addArrangedSubview(section)
        }

        let bottomConstraint = stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            bottomConstraint
        ])

        return view
    }

    private func settingSection(title: String, detail: String, controls: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        stack.addArrangedSubview(detailLabel)

        for control in controls {
            stack.addArrangedSubview(control)
        }

        return stack
    }

    private func fieldRow(control: NSControl, suffix: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        control.widthAnchor.constraint(equalToConstant: 96).isActive = true
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
