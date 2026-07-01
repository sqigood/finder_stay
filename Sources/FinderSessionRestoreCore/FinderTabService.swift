import Foundation

public protocol FinderTabServicing {
    func captureTabs(forWindowTitle title: String?, fallback: TargetLocation) -> [FinderTabSnapshot]
    func openAdditionalTab(_ location: TargetLocation, delay: TimeInterval) throws
    func selectTab(at index: Int, delay: TimeInterval, report: inout RestoreReport)
}

public final class FinderTabService: FinderTabServicing {
    private let runner: AppleScriptRunning

    public init(runner: AppleScriptRunning = AppleScriptRunner()) {
        self.runner = runner
    }

    public func captureTabs(forWindowTitle title: String?, fallback: TargetLocation) -> [FinderTabSnapshot] {
        // Finder does not expose tab target URLs reliably through public AppleScript on all macOS versions.
        // The fallback records the active Finder target as tab 0, while restoration still attempts extra tabs
        // if future snapshots contain them.
        [FinderTabSnapshot(location: fallback)]
    }

    public func openAdditionalTab(_ location: TargetLocation, delay: TimeInterval) throws {
        _ = try runner.run("""
        tell application "System Events"
            tell process "Finder"
                keystroke "t" using command down
            end tell
        end tell
        """)
        Thread.sleep(forTimeInterval: delay)

        if let url = location.url, !url.isFileURL {
            _ = try runner.run("""
            tell application "Finder"
                open location \(AppleScriptEscaper.quotedString(url.absoluteString))
            end tell
            """)
            return
        }

        guard let path = location.path ?? location.url?.path else {
            return
        }

        _ = try runner.run("""
        tell application "Finder"
            set target of front Finder window to POSIX file \(AppleScriptEscaper.quotedString(path))
        end tell
        """)
    }

    public func selectTab(at index: Int, delay: TimeInterval, report: inout RestoreReport) {
        guard index > 0 else {
            return
        }

        do {
            for _ in 0..<index {
                _ = try runner.run("""
                tell application "System Events"
                    tell process "Finder"
                        keystroke tab using {control down, shift down}
                    end tell
                end tell
                """)
                Thread.sleep(forTimeInterval: delay)
            }
        } catch {
            report.addWarning(RestoreWarning(
                code: .unsupportedTabs,
                message: "The saved active Finder tab could not be reselected."
            ))
        }
    }
}
