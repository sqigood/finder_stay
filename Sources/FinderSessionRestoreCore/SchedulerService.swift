import Foundation

public final class SchedulerService {
    private var timer: Timer?
    private var isSaving = false
    private let settingsStore: SettingsStore
    private let recorder: FinderSessionRecorder
    private let queue = DispatchQueue(label: "FinderSessionRestore.Scheduler")

    public init(settingsStore: SettingsStore, recorder: FinderSessionRecorder) {
        self.settingsStore = settingsStore
        self.recorder = recorder
    }

    public func start() {
        stop()
        let settings = settingsStore.load()
        guard settings.autoSaveEnabled else {
            return
        }
        let interval = settings.recordingIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.saveIfIdle()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func saveIfIdle() {
        queue.async { [weak self] in
            guard let self, !self.isSaving else {
                return
            }
            self.isSaving = true
            defer { self.isSaving = false }
            _ = try? self.recorder.recordNow()
        }
    }
}
