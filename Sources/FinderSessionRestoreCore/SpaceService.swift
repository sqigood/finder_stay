import AppKit
import CoreGraphics
import Foundation

public protocol SpaceServicing {
    func captureSpace(forWindowID id: String?, title: String?, bounds: WindowBounds) -> SpaceSnapshot
    func prepareRestore(to space: SpaceSnapshot?, report: inout RestoreReport) -> Bool
    func currentSpaceID() -> UInt64?
    func allDesktopSpaceIDs() -> [UInt64]
    func switchToSpace(_ spaceID: UInt64) -> Bool
}

public extension SpaceServicing {
    func currentSpaceID() -> UInt64? { nil }
    func allDesktopSpaceIDs() -> [UInt64] { [] }
    func switchToSpace(_ spaceID: UInt64) -> Bool { false }
}

public final class SpaceService: SpaceServicing {
    private let skyLight: SkyLightSpaceClient?

    public init() {
        self.skyLight = SkyLightSpaceClient()
    }

    public func captureSpace(forWindowID id: String?, title: String?, bounds: WindowBounds) -> SpaceSnapshot {
        let skyLight = skyLight ?? SkyLightSpaceClient()
        if let windowNumber = id.flatMap(UInt32.init),
           let spaceID = skyLight?.spaceID(forWindowNumber: windowNumber) {
            return SpaceSnapshot(
                id: String(spaceID),
                index: nil,
                rawWorkspaceValue: String(spaceID),
                restoreSupported: true,
                warning: nil
            )
        }

        let visibleWindows = finderWindows(onScreenOnly: true)
        let allWindows = finderWindows(onScreenOnly: false)

        let visibleWindow = visibleWindows.first { matches($0, title: title, bounds: bounds) }

        if visibleWindow != nil {
            let currentSpaceID = skyLight?.currentSpaceID()
            return SpaceSnapshot(
                id: currentSpaceID.map(String.init) ?? "current-space",
                index: nil,
                rawWorkspaceValue: currentSpaceID.map(String.init),
                restoreSupported: currentSpaceID != nil,
                warning: currentSpaceID == nil ? "Current Desktop identity could not be read; this window will not be restored automatically." : nil
            )
        }

        let matchingWindow = allWindows.first { matches($0, title: title, bounds: bounds) }

        let workspace = matchingWindow?["kCGWindowWorkspace"] ?? matchingWindow?["CGWindowWorkspace"]
        let raw = workspace.map { String(describing: $0) }

        if raw == nil && !hasUsableWindowGeometry(visibleWindows + allWindows) {
            return SpaceSnapshot(
                id: nil,
                index: nil,
                rawWorkspaceValue: nil,
                restoreSupported: true,
                warning: "Finder window Space metadata was not available; this window will not be restored automatically."
            )
        }

        return SpaceSnapshot(
            id: raw,
            index: nil,
            rawWorkspaceValue: raw,
            restoreSupported: false,
            warning: "This Finder window was not visible on the current Space when saved, and this build cannot reliably restore windows to other Spaces."
        )
    }

    public func prepareRestore(to space: SpaceSnapshot?, report: inout RestoreReport) -> Bool {
        guard let space else {
            report.addWarning(RestoreWarning(
                code: .spaceRestoreUnavailable,
                message: "Saved window has no Desktop identity, so it was not restored to avoid opening it on the wrong Desktop."
            ))
            return false
        }

        guard space.restoreSupported else {
            if space.id != nil || space.rawWorkspaceValue != nil {
                report.addWarning(RestoreWarning(
                    code: .spaceRestoreUnavailable,
                    message: space.warning ?? "Space restore is unavailable on this macOS version.",
                    targetDescription: space.rawWorkspaceValue ?? space.id
                ))
            }
            return false
        }

        guard let rawWorkspaceValue = space.rawWorkspaceValue,
              let spaceID = UInt64(rawWorkspaceValue) else {
            report.addWarning(RestoreWarning(
                code: .spaceRestoreUnavailable,
                message: "Saved window does not include a real Desktop identity, so it was not restored to avoid opening it on the wrong Desktop.",
                targetDescription: space.rawWorkspaceValue ?? space.id
            ))
            return false
        }

        guard switchToSpace(spaceID) else {
            report.addWarning(RestoreWarning(
                code: .spaceRestoreUnavailable,
                message: "Saved Desktop could not be activated, so the window was not restored to avoid opening it on the wrong Desktop.",
                targetDescription: rawWorkspaceValue
            ))
            return false
        }

        return true
    }

    public func currentSpaceID() -> UInt64? {
        skyLight?.currentSpaceID() ?? SkyLightSpaceClient()?.currentSpaceID()
    }

    public func allDesktopSpaceIDs() -> [UInt64] {
        skyLight?.allDesktopSpaceIDs() ?? SkyLightSpaceClient()?.allDesktopSpaceIDs() ?? []
    }

    public func switchToSpace(_ spaceID: UInt64) -> Bool {
        skyLight?.switchToSpace(spaceID) ?? SkyLightSpaceClient()?.switchToSpace(spaceID) ?? false
    }

    private func finderWindows(onScreenOnly: Bool) -> [[String: Any]] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        let finderPIDs = Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder")
            .map(\.processIdentifier))

        return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { window in
                if let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                   finderPIDs.contains(ownerPID) {
                    return true
                }
                let owner = window[kCGWindowOwnerName as String] as? String
                return owner == "Finder" || owner == "访达"
            }
    }

    private func matches(_ window: [String: Any], title: String?, bounds: WindowBounds) -> Bool {
        if let title,
           let name = window[kCGWindowName as String] as? String,
           name == title {
            return true
        }
        return approximatelyMatches(window, bounds: bounds)
    }

    private func approximatelyMatches(_ window: [String: Any], bounds: WindowBounds) -> Bool {
        guard let dict = window[kCGWindowBounds as String] as? [String: Any],
              let x = dict["X"] as? Double,
              let y = dict["Y"] as? Double,
              let width = dict["Width"] as? Double,
              let height = dict["Height"] as? Double else {
            return false
        }

        return abs(x - bounds.x) < 8 &&
            abs(y - bounds.y) < 8 &&
            abs(width - bounds.width) < 12 &&
            abs(height - bounds.height) < 12
    }

    private func hasUsableWindowGeometry(_ windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            window[kCGWindowBounds as String] is [String: Any]
        }
    }
}

private final class SkyLightSpaceClient {
    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> CFArray?
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> CFArray?
    private typealias ManagedDisplaySetCurrentSpaceFunction = @convention(c) (Int32, CFString, UInt64) -> Int32

    private let connection: Int32
    private let copySpacesForWindows: CopySpacesForWindowsFunction?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunction?
    private let managedDisplaySetCurrentSpace: ManagedDisplaySetCurrentSpaceFunction?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            return nil
        }

        let connectionSymbol = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID")
        guard let connectionSymbol else {
            return nil
        }

        let connectionFunction = unsafeBitCast(connectionSymbol, to: MainConnectionFunction.self)
        connection = connectionFunction()
        copySpacesForWindows = Self.loadSymbol(
            handle,
            primary: "SLSCopySpacesForWindows",
            fallback: "CGSCopySpacesForWindows",
            as: CopySpacesForWindowsFunction.self
        )
        copyManagedDisplaySpaces = Self.loadSymbol(
            handle,
            primary: "SLSCopyManagedDisplaySpaces",
            fallback: "CGSCopyManagedDisplaySpaces",
            as: CopyManagedDisplaySpacesFunction.self
        )
        managedDisplaySetCurrentSpace = Self.loadSymbol(
            handle,
            primary: "SLSManagedDisplaySetCurrentSpace",
            fallback: "CGSManagedDisplaySetCurrentSpace",
            as: ManagedDisplaySetCurrentSpaceFunction.self
        )
    }

    func spaceID(forWindowNumber windowNumber: UInt32) -> UInt64? {
        guard let copySpacesForWindows else {
            return nil
        }

        let windows = [NSNumber(value: windowNumber)] as CFArray
        guard let spaces = copySpacesForWindows(connection, 7, windows) as? [Any] else {
            return nil
        }
        return spaces.compactMap(Self.uint64Value).first
    }

    func currentSpaceID() -> UInt64? {
        managedDisplaySpaces().compactMap { display in
            guard let currentSpace = display["Current Space"] as? [String: Any] else {
                return nil
            }
            return Self.uint64Value(currentSpace["ManagedSpaceID"] ?? currentSpace["id64"])
        }.first
    }

    func allDesktopSpaceIDs() -> [UInt64] {
        var ids: [UInt64] = []
        for display in managedDisplaySpaces() {
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }
            for space in spaces {
                if let type = space["type"] as? NSNumber, type.intValue != 0 {
                    continue
                }
                guard let id = Self.uint64Value(space["ManagedSpaceID"] ?? space["id64"]),
                      !ids.contains(id) else {
                    continue
                }
                ids.append(id)
            }
        }
        return ids
    }

    func switchToSpace(_ spaceID: UInt64) -> Bool {
        guard let managedDisplaySetCurrentSpace,
              let displayID = displayIdentifier(containingSpaceID: spaceID) else {
            return false
        }

        return managedDisplaySetCurrentSpace(connection, displayID as CFString, spaceID) == 0
    }

    private func displayIdentifier(containingSpaceID spaceID: UInt64) -> String? {
        for display in managedDisplaySpaces() {
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }
            let containsSpace = spaces.contains { space in
                Self.uint64Value(space["ManagedSpaceID"] ?? space["id64"]) == spaceID
            }
            if containsSpace {
                return display["Display Identifier"] as? String
            }
        }
        return nil
    }

    private func managedDisplaySpaces() -> [[String: Any]] {
        guard let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return []
        }
        return displays
    }

    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, primary: String, fallback: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(handle, primary) ?? dlsym(handle, fallback) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let int = value as? Int {
            return UInt64(int)
        }
        if let uint64 = value as? UInt64 {
            return uint64
        }
        if let string = value as? String {
            return UInt64(string)
        }
        return nil
    }
}
