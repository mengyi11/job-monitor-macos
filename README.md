# Job Monitor for macOS

A lightweight floating macOS job-monitoring widget. Users can add company career URLs, choose internship role categories, and review job alerts from a compact desktop bubble.

## Install

1. Download the latest DMG from **Releases**.
2. Drag **Job Monitor.app** into Applications.
3. On first launch, right-click the app and choose **Open** if macOS shows an unidentified-developer warning.
4. Open the floating **M** icon and configure the companies and role categories you want to monitor.

## Current beta limitation

This first beta contains the desktop UI, local configuration, alert history, and alert-file watcher. Automated website checking still requires an external scheduler that writes matching jobs to the app's `job-alert.json`. A self-contained background checker is planned for a later release.

User data is stored locally in:

```text
~/Library/Application Support/JobMonitor/
```

No browser cookies or personal job history are included in the release.

## Build

Requires the macOS Command Line Tools:

```bash
xcrun clang -fobjc-arc -framework Cocoa work/MicronJobWidget.m \
  -o "work/Job Monitor.app/Contents/MacOS/MicronJobWidget"
```

## License

MIT
