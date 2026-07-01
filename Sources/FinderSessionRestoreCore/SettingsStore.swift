import Foundation

public final class SettingsStore {
    public let settingsURL: URL
    private let baseDirectory: URL

    public init(baseDirectory: URL = SessionStore.defaultBaseDirectory()) {
        self.baseDirectory = baseDirectory
        self.settingsURL = baseDirectory.appendingPathComponent("settings.json")
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONCoding.decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return normalized(settings)
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(normalized(settings))
        try data.write(to: settingsURL, options: [.atomic])
    }

    private func normalized(_ settings: AppSettings) -> AppSettings {
        AppSettings(
            autoSaveEnabled: settings.autoSaveEnabled,
            recordingIntervalSeconds: max(30, settings.recordingIntervalSeconds),
            restoreMode: .mergeWithCurrentWindows,
            networkReconnectTimeoutSeconds: max(1, settings.networkReconnectTimeoutSeconds),
            historyCount: min(max(settings.historyCount, 0), 100),
            launchAtLogin: settings.launchAtLogin,
            soundEffectsEnabled: settings.soundEffectsEnabled
        )
    }
}
