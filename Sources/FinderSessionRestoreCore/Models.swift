import Foundation

public enum RestoreMode: String, CaseIterable, Equatable {
    case mergeWithCurrentWindows

    public var title: String {
        switch self {
        case .mergeWithCurrentWindows:
            return "Restore missing Finder windows"
        }
    }
}

extension RestoreMode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "mergeWithCurrentWindows", "replaceCurrentWindows":
            self = .mergeWithCurrentWindows
        default:
            self = .mergeWithCurrentWindows
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(RestoreMode.mergeWithCurrentWindows.rawValue)
    }
}

public enum TargetLocationKind: String, Codable, Equatable {
    case local
    case mountedVolume
    case network
    case remote
    case unknown
}

public struct TargetLocation: Codable, Equatable, Hashable {
    public var url: URL?
    public var path: String?
    public var kind: TargetLocationKind

    public init(url: URL?, path: String?, kind: TargetLocationKind) {
        self.url = url
        self.path = path
        self.kind = kind
    }

    public static func classify(url: URL?, path: String? = nil) -> TargetLocation {
        let normalizedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = normalizedPath?.isEmpty == true ? nil : normalizedPath
        let cleanURL = url?.absoluteString.isEmpty == true ? nil : url
        let resolvedPath = cleanPath ?? (cleanURL?.isFileURL == true ? cleanURL?.path : nil)
        let scheme = cleanURL?.scheme?.lowercased()

        if let scheme, ["smb", "afp", "nfs"].contains(scheme) {
            return TargetLocation(url: url, path: resolvedPath, kind: .network)
        }

        if let scheme, ["http", "https", "webdav", "davs"].contains(scheme) {
            return TargetLocation(url: url, path: resolvedPath, kind: .remote)
        }

        if let resolvedPath, resolvedPath.hasPrefix("/Volumes/") {
            return TargetLocation(url: cleanURL ?? URL(fileURLWithPath: resolvedPath), path: resolvedPath, kind: .mountedVolume)
        }

        if let resolvedPath {
            return TargetLocation(url: cleanURL ?? URL(fileURLWithPath: resolvedPath), path: resolvedPath, kind: .local)
        }

        if let cleanURL {
            return TargetLocation(url: cleanURL, path: nil, kind: .unknown)
        }

        return TargetLocation(url: nil, path: nil, kind: .unknown)
    }

    public var hasConcreteTarget: Bool {
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let url, !url.absoluteString.isEmpty {
            return true
        }
        return false
    }

    public var displayDescription: String? {
        path ?? url?.absoluteString
    }
}

public struct WindowBounds: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DisplaySnapshot: Codable, Equatable {
    public var id: String?
    public var name: String?

    public init(id: String?, name: String?) {
        self.id = id
        self.name = name
    }
}

public struct SpaceSnapshot: Codable, Equatable {
    public var id: String?
    public var index: Int?
    public var rawWorkspaceValue: String?
    public var restoreSupported: Bool
    public var warning: String?

    public init(id: String?, index: Int?, rawWorkspaceValue: String?, restoreSupported: Bool = false, warning: String? = nil) {
        self.id = id
        self.index = index
        self.rawWorkspaceValue = rawWorkspaceValue
        self.restoreSupported = restoreSupported
        self.warning = warning
    }
}

public struct FinderTabSnapshot: Codable, Equatable {
    public var url: URL?
    public var path: String?
    public var kind: TargetLocationKind

    public init(url: URL?, path: String?, kind: TargetLocationKind) {
        self.url = url
        self.path = path
        self.kind = kind
    }

    public init(location: TargetLocation) {
        self.url = location.url
        self.path = location.path
        self.kind = location.kind
    }

    public var location: TargetLocation {
        TargetLocation(url: url, path: path, kind: kind)
    }
}

public struct FinderWindowSnapshot: Codable, Equatable {
    public var id: String?
    public var title: String?
    public var bounds: WindowBounds
    public var display: DisplaySnapshot?
    public var space: SpaceSnapshot?
    public var target: TargetLocation
    public var tabs: [FinderTabSnapshot]
    public var activeTabIndex: Int?

    public init(
        id: String?,
        title: String?,
        bounds: WindowBounds,
        display: DisplaySnapshot?,
        space: SpaceSnapshot?,
        target: TargetLocation,
        tabs: [FinderTabSnapshot],
        activeTabIndex: Int?
    ) {
        self.id = id
        self.title = title
        self.bounds = bounds
        self.display = display
        self.space = space
        self.target = target
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }
}

public struct FinderSessionSnapshot: Codable, Equatable {
    public var schemaVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var windows: [FinderWindowSnapshot]

    public init(schemaVersion: Int = 1, appVersion: String, createdAt: Date = Date(), windows: [FinderWindowSnapshot]) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.windows = windows
    }
}

public struct AppSettings: Codable, Equatable {
    public var recordingIntervalSeconds: TimeInterval
    public var restoreMode: RestoreMode
    public var networkReconnectTimeoutSeconds: TimeInterval
    public var historyCount: Int
    public var launchAtLogin: Bool

    public init(
        recordingIntervalSeconds: TimeInterval = 300,
        restoreMode: RestoreMode = .mergeWithCurrentWindows,
        networkReconnectTimeoutSeconds: TimeInterval = 20,
        historyCount: Int = 10,
        launchAtLogin: Bool = false
    ) {
        self.recordingIntervalSeconds = recordingIntervalSeconds
        self.restoreMode = restoreMode
        self.networkReconnectTimeoutSeconds = networkReconnectTimeoutSeconds
        self.historyCount = historyCount
        self.launchAtLogin = launchAtLogin
    }
}

public enum RestoreWarningCode: String, Codable, Equatable {
    case finderNotRunning
    case noSavedSession
    case permissionMissing
    case targetUnavailable
    case networkReconnectFailed
    case spaceRestoreUnavailable
    case finderAutomationFailed
    case corruptedSnapshot
    case unsupportedTabs
}

public struct RestoreWarning: Codable, Equatable {
    public var code: RestoreWarningCode
    public var message: String
    public var targetDescription: String?

    public init(code: RestoreWarningCode, message: String, targetDescription: String? = nil) {
        self.code = code
        self.message = message
        self.targetDescription = targetDescription
    }
}

public struct RestoreReport: Codable, Equatable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var restoredWindowCount: Int
    public var restoredTabCount: Int
    public var warnings: [RestoreWarning]

    public init(
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        restoredWindowCount: Int = 0,
        restoredTabCount: Int = 0,
        warnings: [RestoreWarning] = []
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.restoredWindowCount = restoredWindowCount
        self.restoredTabCount = restoredTabCount
        self.warnings = warnings
    }

    public var hasWarnings: Bool {
        !warnings.isEmpty
    }

    public var summary: String {
        if warnings.isEmpty {
            return "Restore completed."
        }
        return "Restore completed with \(warnings.count) warning\(warnings.count == 1 ? "" : "s")."
    }

    public mutating func addWarning(_ warning: RestoreWarning) {
        warnings.append(warning)
    }
}

public struct NetworkConnectionResult: Equatable {
    public var location: TargetLocation
    public var isReachable: Bool
    public var warning: RestoreWarning?

    public init(location: TargetLocation, isReachable: Bool, warning: RestoreWarning? = nil) {
        self.location = location
        self.isReachable = isReachable
        self.warning = warning
    }
}
