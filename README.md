# TrainTracker

macOS menu bar app for tracking Austrian (ÖBB) trains in real time.

## Installation

### Homebrew

```bash
brew tap philroli/tap
brew install --cask traintracker
```

TrainTracker is ad-hoc signed (not notarized). On first launch, right-click the app in Finder and choose "Open" to bypass Gatekeeper, or run:

```bash
xattr -dr com.apple.quarantine /Applications/TrainTracker.app
```

### Build from source

Requires Swift 5.9+ / macOS 13+, no third-party dependencies:

```bash
git clone https://github.com/philroli/traintracker
cd traintracker
./rebuild.sh
```

`rebuild.sh` builds a universal binary, assembles `TrainTracker.app`, installs it to `/Applications`, and launches it.

## Usage

TrainTracker lives in the menu bar (no Dock icon). Open **Preferences…** from the menu to:

- Search for and set your from/to stations
- Pick a specific train once one is running, or let it auto-select
- Save routes for one-click switching from the menu bar
- Configure notifications (departure reminder, delay alert, platform change)
- Turn on **Launch at Login**
- Export or import your configuration as JSON

The menu bar title shows the tracked train's emoji, name, and countdown/delay; the dropdown menu shows stop-by-stop progress, lets you switch trains or routes, and refreshes on demand.

## Features

- Real-time tracking against the ÖBB transport API, including delays and platform changes
- Menu bar countdown to departure/arrival, updated every 30 seconds
- Notifications: departure reminder, delay alert, platform change
- Saved routes, switchable directly from the menu bar
- Launch at Login (via `SMAppService`)
- Config export/import as JSON
- Zero third-party dependencies — AppKit, URLSession, UserNotifications, ServiceManagement only

## Architecture

Single Swift Package Manager executable target, split into focused files under `Sources/TrainTracker/`:

| File | Responsibility |
| --- | --- |
| `main.swift` | App entry point |
| `AppDelegate.swift` | App lifecycle |
| `StatusBarController.swift` | Menu bar item, refresh timer, menu building |
| `TrainFetcher.swift` | Journey fetching, train matching, refresh-token caching |
| `OeBBClient.swift` | ÖBB API client |
| `Models.swift` | API response types and internal display types |
| `AppConfig.swift` | Persisted configuration (`UserDefaults`) |
| `ConfigTransfer.swift` | JSON export/import of configuration |
| `NotificationManager.swift` | Departure/delay/platform-change notifications |
| `LoginItemManaging.swift` | Launch-at-Login via `SMAppService` |
| `PreferencesWindowController.swift` / `PreferencesWindowController+Actions.swift` | Preferences UI |

Data source: `https://oebb.rolinek.at/api`

## License

MIT
