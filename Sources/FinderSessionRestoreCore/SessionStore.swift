import Foundation

public final class SessionStore {
    public let baseDirectory: URL
    public let latestSessionURL: URL
    public let latestRestoreReportURL: URL
    public let historyDirectory: URL

    public init(baseDirectory: URL = SessionStore.defaultBaseDirectory()) {
        self.baseDirectory = baseDirectory
        self.latestSessionURL = baseDirectory.appendingPathComponent("latest-session.json")
        self.latestRestoreReportURL = baseDirectory.appendingPathComponent("last-restore-report.json")
        self.historyDirectory = baseDirectory.appendingPathComponent("History", isDirectory: true)
    }

    public static func defaultBaseDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinderSessionRestore", isDirectory: true)
    }

    public func save(_ snapshot: FinderSessionSnapshot, historyCount: Int) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        let data = try JSONCoding.encoder.encode(snapshot)
        try data.write(to: latestSessionURL, options: [.atomic])

        let historyName = Self.historyFileName(for: snapshot.createdAt)
        try data.write(to: historyDirectory.appendingPathComponent(historyName), options: [.atomic])
        try pruneHistory(keep: max(historyCount, 0))
    }

    public func loadLatest() throws -> FinderSessionSnapshot {
        let data = try Data(contentsOf: latestSessionURL)
        return try JSONCoding.decoder.decode(FinderSessionSnapshot.self, from: data)
    }

    public func saveRestoreReport(_ report: RestoreReport) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(report)
        try data.write(to: latestRestoreReportURL, options: [.atomic])
    }

    public func latestSavedDate() -> Date? {
        guard let values = try? latestSessionURL.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: latestSessionURL.path) {
            try FileManager.default.removeItem(at: latestSessionURL)
        }
        if FileManager.default.fileExists(atPath: historyDirectory.path) {
            try FileManager.default.removeItem(at: historyDirectory)
        }
    }

    private func pruneHistory(keep: Int) throws {
        guard keep > 0 else {
            if FileManager.default.fileExists(atPath: historyDirectory.path) {
                try FileManager.default.removeItem(at: historyDirectory)
                try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
            }
            return
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        for stale in sorted.dropFirst(keep) {
            try FileManager.default.removeItem(at: stale)
        }
    }

    private static func historyFileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeDate = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeDate).json"
    }
}
