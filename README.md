# Finder Session Restore

Finder Session Restore is a native macOS menu bar utility that records the current Finder window session and restores the latest saved session on demand.

The app is local-only. It stores session JSON under:

```text
~/Library/Application Support/FinderSessionRestore/
```

## Build

Open the project in Xcode by opening `Package.swift`, or build from Terminal:

```bash
swift build
```

To create a menu-bar `.app` bundle with no Dock icon:

```bash
Scripts/package_app.sh
open .build/FinderSessionRestore.app
```

## Menu

- Save Current Finder State
- Restore Last Finder State
- Settings
- Quit

## Permissions

The app may need these macOS permissions:

- Automation permission to control Finder.
- Accessibility permission to inspect and manipulate Finder windows and tabs.
- Screen Recording permission to read Finder window metadata safely enough to distinguish current Desktop windows from windows on other Desktops.

The Settings window shows the current permission status.

## Data Schema

The latest saved session is written as versioned JSON:

```text
latest-session.json
last-restore-report.json
```

The history folder keeps recent snapshots according to the configured history count. Each restore writes `last-restore-report.json` so skipped windows, permission warnings, and Finder automation failures can be inspected after closing the warning dialog.

## Current Implementation Notes

- Finder window paths, titles, and bounds are captured with AppleScript.
- Window restoration opens missing saved targets and restores bounds. It never closes existing Finder windows.
- Finder tab support is implemented through a dedicated tab service. Current capture stores the active target as tab 0 because Finder does not expose tab target URLs reliably through public AppleScript on all macOS versions. Restore attempts additional tabs when snapshots contain them.
- Space support is isolated behind `SpaceService`. The app records the real macOS Space ID for Finder windows through SkyLight window metadata, switches to that Space before opening a missing saved window, and skips any window without a real Desktop identity so it is not incorrectly recreated on the active Desktop.
- Network and remote targets are preflighted before restore. Failed network reconnects generate warnings and do not block the rest of the restore.

## Manual Test Checklist

1. Save and restore one local Finder window.
2. Save and restore multiple Finder windows.
3. Save and restore one Finder window with multiple tabs.
4. Save and restore windows across at least two macOS Spaces.
5. Save and restore windows across multiple displays if available.
6. Save and restore an SMB Finder location.
7. Test missing network connection behavior.
8. Test missing permissions.
9. Test automatic 5-minute recording.
10. Confirm no Dock icon appears by default.
11. Confirm all user-facing UI is English-only.

## Known Limitations

- macOS does not provide a stable public API for assigning Finder windows to arbitrary Spaces. The app records available workspace metadata and reports restore limitations in the restore report.
- Finder tab target capture is best-effort. The architecture keeps tab handling isolated so a stronger Accessibility implementation can replace the current fallback without changing persistence.
