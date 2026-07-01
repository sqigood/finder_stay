import AppKit
import Foundation

public enum FinderAutomationError: Error, LocalizedError {
    case finderNotRunning
    case invalidScriptOutput
    case currentSpaceWindowListUnavailable
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .finderNotRunning:
            return "Finder is not running."
        case .invalidScriptOutput:
            return "Finder automation returned invalid data."
        case .currentSpaceWindowListUnavailable:
            return "Current Desktop Finder windows could not be read. Grant Accessibility permission and try saving again."
        case .openFailed(let target):
            return "Finder could not open \(target)."
        }
    }
}

public protocol FinderAutomationServicing {
    func isFinderRunning() -> Bool
    func captureFinderWindows(appVersion: String) throws -> [FinderWindowSnapshot]
    func savedWindowAlreadyOpen(_ window: FinderWindowSnapshot) -> Bool
    func restoreWindow(_ window: FinderWindowSnapshot, report: inout RestoreReport) throws
}

public final class FinderAutomationService: FinderAutomationServicing {
    private struct RawWindow: Decodable {
        var id: String?
        var title: String?
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var url: String?
        var path: String?
    }

    private struct VisibleWindow: Decodable {
        var title: String?
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private let runner: AppleScriptRunning
    private let visibleWindowRunner: AppleScriptRunning
    private let tabService: FinderTabServicing
    private let spaceService: SpaceServicing
    private let delay: TimeInterval

    public init(
        runner: AppleScriptRunning = AppleScriptRunner(),
        visibleWindowRunner: AppleScriptRunning = AppleScriptRunner(timeout: 3),
        tabService: FinderTabServicing = FinderTabService(),
        spaceService: SpaceServicing = SpaceService(),
        delay: TimeInterval = 0.35
    ) {
        self.runner = runner
        self.visibleWindowRunner = visibleWindowRunner
        self.tabService = tabService
        self.spaceService = spaceService
        self.delay = delay
    }

    public func isFinderRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty
    }

    public func captureFinderWindows(appVersion: String) throws -> [FinderWindowSnapshot] {
        guard isFinderRunning() else {
            throw FinderAutomationError.finderNotRunning
        }

        let output = try runner.run(Self.captureScript)
        guard let data = output.data(using: .utf8) else {
            throw FinderAutomationError.invalidScriptOutput
        }

        let rawWindows = try JSONDecoder().decode([RawWindow].self, from: data)
        return rawWindows.map { raw in
            let targetURL = raw.url.flatMap(URL.init(string:))
            let target = TargetLocation.classify(url: targetURL, path: raw.path)
            let bounds = WindowBounds(x: raw.x, y: raw.y, width: raw.width, height: raw.height)
            let tabs = tabService.captureTabs(forWindowTitle: raw.title, fallback: target)
            let space = spaceService.captureSpace(forWindowID: raw.id, title: raw.title, bounds: bounds)

            return FinderWindowSnapshot(
                id: raw.id,
                title: raw.title,
                bounds: bounds,
                display: nil,
                space: space,
                target: target,
                tabs: tabs.isEmpty ? [FinderTabSnapshot(location: target)] : tabs,
                activeTabIndex: 0
            )
        }
    }

    private func captureVisibleFinderWindows() throws -> [VisibleWindow] {
        do {
            let output = try visibleWindowRunner.run(Self.visibleWindowScript)
            guard let data = output.data(using: .utf8) else {
                throw FinderAutomationError.invalidScriptOutput
            }
            return try JSONDecoder().decode([VisibleWindow].self, from: data)
        } catch {
            throw FinderAutomationError.currentSpaceWindowListUnavailable
        }
    }

    public func savedWindowAlreadyOpen(_ window: FinderWindowSnapshot) -> Bool {
        guard let path = window.target.path ?? (window.target.url?.isFileURL == true ? window.target.url?.path : nil) else {
            return false
        }

        guard let output = try? runner.run(Self.openWindowTargetsScript) else {
            return false
        }

        let openPaths = Set(output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })

        return openPaths.contains(path)
    }

    public func restoreWindow(_ window: FinderWindowSnapshot, report: inout RestoreReport) throws {
        try open(location: window.target)
        Thread.sleep(forTimeInterval: window.target.kind == .mountedVolume ? max(delay, 1.2) : delay)
        try setFrontWindowBounds(window.bounds)
        report.restoredWindowCount += 1

        let tabs = window.tabs.isEmpty ? [FinderTabSnapshot(location: window.target)] : window.tabs
        if tabs.count > 1 {
            for tab in tabs.dropFirst() {
                do {
                    try tabService.openAdditionalTab(tab.location, delay: delay)
                    report.restoredTabCount += 1
                } catch {
                    report.addWarning(RestoreWarning(
                        code: .unsupportedTabs,
                        message: "Finder tab restoration failed for one saved tab.",
                        targetDescription: tab.url?.absoluteString ?? tab.path
                    ))
                }
            }
        }

        report.restoredTabCount += min(tabs.count, 1)
        if let activeTabIndex = window.activeTabIndex, activeTabIndex > 0 {
            tabService.selectTab(at: activeTabIndex, delay: delay, report: &report)
        }
    }

    private func open(location: TargetLocation) throws {
        if let url = location.url, !url.isFileURL {
            try openWithWorkspace(url, targetDescription: url.absoluteString)
            return
        }

        guard let path = location.path ?? location.url?.path else {
            return
        }

        try openWithWorkspace(URL(fileURLWithPath: path), targetDescription: path)
    }

    private func openWithWorkspace(_ url: URL, targetDescription: String) throws {
        let openBlock = {
            NSWorkspace.shared.open(url)
        }
        let opened = Thread.isMainThread ? openBlock() : DispatchQueue.main.sync(execute: openBlock)
        guard opened else {
            throw FinderAutomationError.openFailed(targetDescription)
        }
    }

    private func setFrontWindowBounds(_ bounds: WindowBounds) throws {
        let right = bounds.x + bounds.width
        let bottom = bounds.y + bounds.height
        _ = try runner.run("""
        with timeout of 5 seconds
            tell application "Finder"
                if (count of Finder windows) > 0 then
                    set bounds of front Finder window to {\(Int(bounds.x)), \(Int(bounds.y)), \(Int(right)), \(Int(bottom))}
                end if
            end tell
        end timeout
        """)
    }

    private static func matches(_ raw: RawWindow, visible: VisibleWindow) -> Bool {
        if let rawTitle = raw.title,
           let visibleTitle = visible.title,
           !rawTitle.isEmpty,
           rawTitle == visibleTitle {
            return true
        }

        return abs(raw.x - visible.x) < 8 &&
            abs(raw.y - visible.y) < 8 &&
            abs(raw.width - visible.width) < 12 &&
            abs(raw.height - visible.height) < 12
    }

    private static let captureScript = """
    on jsonString(valueText)
        set s to valueText as string
        set s to my replaceText("\\\\", "\\\\\\\\", s)
        set s to my replaceText("\\"", "\\\\\\"", s)
        set s to my replaceText(return, "\\\\n", s)
        set s to my replaceText(linefeed, "\\\\n", s)
        set s to my replaceText(tab, "\\\\t", s)
        return "\\"" & s & "\\""
    end jsonString

    on replaceText(findText, replaceText, sourceText)
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to findText
        set textItems to every text item of sourceText
        set AppleScript's text item delimiters to replaceText
        set resultText to textItems as text
        set AppleScript's text item delimiters to oldDelimiters
        return resultText
    end replaceText

    tell application "Finder"
        set output to "["
        set firstItem to true
        set windowCount to count of Finder windows
        repeat with windowIndex from 1 to windowCount
            set finderWindow to Finder window windowIndex
            set b to bounds of finderWindow
            if class of item 1 of b is list then set b to item 1 of b
            set leftEdge to item 1 of b
            set topEdge to item 2 of b
            set rightEdge to item 3 of b
            set bottomEdge to item 4 of b
            set windowId to ""
            try
                set windowId to id of finderWindow as string
            end try
            set windowTitle to ""
            try
                set windowTitle to name of finderWindow as string
            end try
            set targetURL to ""
            set targetPath to ""
            try
                set targetURL to URL of target of finderWindow as string
            end try
            try
                set targetPath to POSIX path of (target of finderWindow as alias)
            end try

            if firstItem is false then set output to output & ","
            set firstItem to false
            set output to output & "{"
            set output to output & "\\"id\\":" & my jsonString(windowId) & ","
            set output to output & "\\"title\\":" & my jsonString(windowTitle) & ","
            set output to output & "\\"x\\":" & (leftEdge as string) & ","
            set output to output & "\\"y\\":" & (topEdge as string) & ","
            set output to output & "\\"width\\":" & ((rightEdge - leftEdge) as string) & ","
            set output to output & "\\"height\\":" & ((bottomEdge - topEdge) as string) & ","
            set output to output & "\\"url\\":" & my jsonString(targetURL) & ","
            set output to output & "\\"path\\":" & my jsonString(targetPath)
            set output to output & "}"
        end repeat
        set output to output & "]"
        return output
    end tell
    """

    private static let openWindowTargetsScript = """
    tell application "Finder"
        set output to ""
        repeat with windowIndex from 1 to count of Finder windows
            set finderWindow to Finder window windowIndex
            try
                set output to output & (POSIX path of (target of finderWindow as alias)) & linefeed
            end try
        end repeat
        return output
    end tell
    """

    private static let visibleWindowScript = """
    on jsonString(valueText)
        set s to valueText as string
        set s to my replaceText("\\\\", "\\\\\\\\", s)
        set s to my replaceText("\\"", "\\\\\\"", s)
        set s to my replaceText(return, "\\\\n", s)
        set s to my replaceText(linefeed, "\\\\n", s)
        set s to my replaceText(tab, "\\\\t", s)
        return "\\"" & s & "\\""
    end jsonString

    on replaceText(findText, replaceText, sourceText)
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to findText
        set textItems to every text item of sourceText
        set AppleScript's text item delimiters to replaceText
        set resultText to textItems as text
        set AppleScript's text item delimiters to oldDelimiters
        return resultText
    end replaceText

    tell application "System Events"
        tell process "Finder"
            set output to "["
            set firstItem to true
            repeat with windowIndex from 1 to count of windows
                set finderWindow to window windowIndex
                set p to position of finderWindow
                set s to size of finderWindow
                set windowTitle to ""
                try
                    set windowTitle to name of finderWindow as string
                end try

                if firstItem is false then set output to output & ","
                set firstItem to false
                set output to output & "{"
                set output to output & "\\"title\\":" & my jsonString(windowTitle) & ","
                set output to output & "\\"x\\":" & ((item 1 of p) as string) & ","
                set output to output & "\\"y\\":" & ((item 2 of p) as string) & ","
                set output to output & "\\"width\\":" & ((item 1 of s) as string) & ","
                set output to output & "\\"height\\":" & ((item 2 of s) as string)
                set output to output & "}"
            end repeat
            set output to output & "]"
            return output
        end tell
    end tell
    """
}
