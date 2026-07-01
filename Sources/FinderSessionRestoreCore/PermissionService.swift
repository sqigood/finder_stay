import AppKit
import ApplicationServices
import Foundation

public struct PermissionStatus: Equatable {
    public var automationAllowed: Bool
    public var accessibilityAllowed: Bool
    public var screenRecordingLikelyAllowed: Bool

    public init(automationAllowed: Bool, accessibilityAllowed: Bool, screenRecordingLikelyAllowed: Bool) {
        self.automationAllowed = automationAllowed
        self.accessibilityAllowed = accessibilityAllowed
        self.screenRecordingLikelyAllowed = screenRecordingLikelyAllowed
    }

    public var missingWarnings: [RestoreWarning] {
        var warnings: [RestoreWarning] = []
        if !automationAllowed {
            warnings.append(RestoreWarning(code: .permissionMissing, message: "Finder automation permission is required."))
        }
        return warnings
    }
}

public final class PermissionService {
    private let runner: AppleScriptRunning

    public init(runner: AppleScriptRunning = AppleScriptRunner()) {
        self.runner = runner
    }

    public func currentStatus() -> PermissionStatus {
        PermissionStatus(
            automationAllowed: canControlFinder(),
            accessibilityAllowed: AXIsProcessTrusted(),
            screenRecordingLikelyAllowed: canReadWindowNames()
        )
    }

    public func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func requestScreenRecordingPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func canControlFinder() -> Bool {
        do {
            _ = try runner.run("""
            tell application "Finder"
                return count of Finder windows as string
            end tell
            """)
            return true
        } catch {
            return false
        }
    }

    private func canReadWindowNames() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            let name = window[kCGWindowName as String] as? String
            return owner == "Finder" && name != nil
        }
    }
}
