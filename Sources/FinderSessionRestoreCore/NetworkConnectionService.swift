import AppKit
import Foundation

public protocol LocationReachabilityChecking {
    func isReachable(_ location: TargetLocation) -> Bool
}

public struct FileSystemReachabilityChecker: LocationReachabilityChecking {
    public init() {}

    public func isReachable(_ location: TargetLocation) -> Bool {
        if let path = location.path {
            return FileManager.default.fileExists(atPath: path)
        }
        if let url = location.url, url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return false
    }
}

public protocol NetworkMounting {
    func attemptMount(_ url: URL)
}

public struct WorkspaceNetworkMounter: NetworkMounting {
    public init() {}

    public func attemptMount(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

public final class NetworkConnectionService {
    private let reachabilityChecker: LocationReachabilityChecking
    private let mounter: NetworkMounting
    private let sleeper: (TimeInterval) -> Void

    public init(
        reachabilityChecker: LocationReachabilityChecking = FileSystemReachabilityChecker(),
        mounter: NetworkMounting = WorkspaceNetworkMounter(),
        sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.reachabilityChecker = reachabilityChecker
        self.mounter = mounter
        self.sleeper = sleeper
    }

    public func preflight(_ location: TargetLocation, timeout: TimeInterval) -> NetworkConnectionResult {
        switch location.kind {
        case .local:
            if reachabilityChecker.isReachable(location) {
                return NetworkConnectionResult(location: location, isReachable: true)
            }
            return NetworkConnectionResult(
                location: location,
                isReachable: false,
                warning: RestoreWarning(
                    code: .targetUnavailable,
                    message: "Saved target no longer exists.",
                    targetDescription: location.displayDescription
                )
            )

        case .mountedVolume:
            return NetworkConnectionResult(location: location, isReachable: true)

        case .network, .remote:
            if reachabilityChecker.isReachable(location) {
                return NetworkConnectionResult(location: location, isReachable: true)
            }

            if let url = location.url {
                mounter.attemptMount(url)
            }

            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if reachabilityChecker.isReachable(location) {
                    return NetworkConnectionResult(location: location, isReachable: true)
                }
                sleeper(0.25)
            }

            return NetworkConnectionResult(
                location: location,
                isReachable: false,
                warning: RestoreWarning(
                    code: .networkReconnectFailed,
                    message: "Network or remote target could not be reconnected before the timeout.",
                    targetDescription: location.displayDescription
                )
            )

        case .unknown:
            return NetworkConnectionResult(location: location, isReachable: true)
        }
    }
}
