import AppKit
import FinderSessionRestoreCore

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let sessionStore: SessionStore
    private let permissionService: PermissionService

    private let intervalField = NSTextField()
    private let timeoutField = NSTextField()
    private let historyField = NSTextField()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let lastSavedLabel = NSTextField(labelWithString: "")

    init(settingsStore: SettingsStore, sessionStore: SessionStore, permissionService: PermissionService) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.permissionService = permissionService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
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
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24)
        ])

        stack.addArrangedSubview(row(label: "Recording interval", control: intervalField, suffix: "seconds"))
        stack.addArrangedSubview(row(label: "Network reconnect timeout", control: timeoutField, suffix: "seconds"))
        stack.addArrangedSubview(row(label: "Keep session history count", control: historyField, suffix: "snapshots"))
        stack.addArrangedSubview(launchAtLoginCheckbox)

        let permissionsTitle = NSTextField(labelWithString: "Permission status")
        permissionsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(permissionsTitle)
        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 4
        stack.addArrangedSubview(permissionLabel)

        stack.addArrangedSubview(lastSavedLabel)

        let dataButtonRow = NSStackView()
        dataButtonRow.orientation = .horizontal
        dataButtonRow.spacing = 8
        let openDataButton = NSButton(title: "Open Data Folder", target: self, action: #selector(openDataFolder))
        let resetButton = NSButton(title: "Reset Saved Sessions", target: self, action: #selector(resetSavedSessions))
        dataButtonRow.addArrangedSubview(openDataButton)
        dataButtonRow.addArrangedSubview(resetButton)
        stack.addArrangedSubview(dataButtonRow)

        let permissionButtonRow = NSStackView()
        permissionButtonRow.orientation = .horizontal
        permissionButtonRow.spacing = 8
        let accessibilityButton = NSButton(title: "Request Accessibility Permission", target: self, action: #selector(requestAccessibility))
        let screenRecordingButton = NSButton(title: "Request Screen Recording Permission", target: self, action: #selector(requestScreenRecording))
        let saveButton = NSButton(title: "Save Settings", target: self, action: #selector(saveSettings))
        permissionButtonRow.addArrangedSubview(accessibilityButton)
        permissionButtonRow.addArrangedSubview(screenRecordingButton)
        permissionButtonRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(permissionButtonRow)
    }

    private func row(label: String, control: NSView, suffix: String?) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 190).isActive = true
        control.widthAnchor.constraint(equalToConstant: 180).isActive = true
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(control)

        if let suffix {
            stack.addArrangedSubview(NSTextField(labelWithString: suffix))
        }

        return stack
    }

    private func loadSettings() {
        let settings = settingsStore.load()
        intervalField.stringValue = String(Int(settings.recordingIntervalSeconds))
        timeoutField.stringValue = String(Int(settings.networkReconnectTimeoutSeconds))
        historyField.stringValue = String(settings.historyCount)
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off

        let permissions = permissionService.currentStatus()
        permissionLabel.stringValue = [
            permissions.automationAllowed ? "Automation permission: Granted" : "Automation permission: Required for Finder control",
            permissions.accessibilityAllowed ? "Accessibility permission: Granted" : "Accessibility permission: Required to read and restore Finder window positions",
            permissions.screenRecordingLikelyAllowed ? "Screen Recording permission: Finder window metadata available" : "Screen Recording permission: Required to distinguish current Desktop windows safely"
        ].joined(separator: "\n")

        if let date = sessionStore.latestSavedDate() {
            lastSavedLabel.stringValue = "Last saved session: \(date.formatted(date: .abbreviated, time: .standard))"
        } else {
            lastSavedLabel.stringValue = "Last saved session: Never"
        }
    }

    @objc private func saveSettings() {
        let settings = AppSettings(
            recordingIntervalSeconds: TimeInterval(Int(intervalField.stringValue) ?? 300),
            restoreMode: .mergeWithCurrentWindows,
            networkReconnectTimeoutSeconds: TimeInterval(Int(timeoutField.stringValue) ?? 20),
            historyCount: Int(historyField.stringValue) ?? 10,
            launchAtLogin: launchAtLoginCheckbox.state == .on
        )
        try? settingsStore.save(settings)
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
