# TrainTracker

macOS menu bar app for tracking Austrian (ÖBB) trains in real time.

## Installation

### Homebrew

```bash
brew tap PhilRoli/tap
brew install --cask traintracker
```

TrainTracker is ad-hoc signed, not notarized (no Apple Developer ID). On first launch macOS will block it. Either run:

```bash
xattr -dr com.apple.quarantine /Applications/TrainTracker.app
```

or try to open it once, then allow it under **System Settings → Privacy & Security → Open Anyway** (on macOS 15+ right-click → Open no longer bypasses Gatekeeper).

### Build from source

Requires Swift 5.9+ / macOS 13+, no third-party dependencies:

```bash
git clone https://github.com/PhilRoli/traintracker
cd traintracker
./rebuild.sh
```

`rebuild.sh` is a developer convenience: it builds a universal binary, assembles `TrainTracker.app`, replaces `/Applications/TrainTracker.app`, stops any running instance, and launches it.

### Development

```bash
swift build
swift test
swiftlint --strict   # brew install swiftlint
```

### Uninstall

Quit the app, delete `/Applications/TrainTracker.app` (or `brew uninstall --cask traintracker`), and optionally reset its settings with `defaults delete traintracker`.

## Usage

TrainTracker lives in the menu bar (no Dock icon). Open **Preferences…** from the menu to:

- Search for and set your from/to stations
- Pick a specific train once one is running, or let it auto-select
- Save routes for one-click switching from the menu bar
- Configure notifications (departure, delay, arrival, and transfer reminders, platform change); every setting applies immediately
- Turn on **Launch at Login**
- Export or import your configuration as JSON

The menu bar title shows the tracked train's emoji, name, and countdown/delay; the dropdown menu shows stop-by-stop progress, lets you switch trains or routes, and refreshes on demand.

## Features

- Real-time tracking against the ÖBB transport API, including delays and platform changes
- Menu bar countdown to departure/arrival; polls every 30s while a train is close or en route, less often otherwise, and pauses after arrival
- Refreshes on wake from sleep and when the network returns; shows when the service can't be reached instead of "train not found"
- Notifications: departure, delay, arrival and transfer reminders, platform change
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
| `StatusBarController.swift` / `StatusBarController+Menu.swift` | Menu bar item, adaptive refresh scheduling, menu building |
| `TrainFetcher.swift` / `TrainFetcher+Building.swift` | Journey fetching, train matching, refresh-token caching |
| `OeBBClient.swift` | ÖBB API client |
| `Models.swift` | API response types and internal display types |
| `AppConfig.swift` | Persisted configuration (`UserDefaults`) |
| `ConfigTransfer.swift` | JSON export/import of configuration |
| `NotificationManager.swift` | Departure/delay/platform-change notifications |
| `LoginItemManaging.swift` | Launch-at-Login via `SMAppService` |
| `PreferencesWindowController*.swift` | Preferences UI (live-apply; routes, notifications, config transfer) |
| `PreferencesLogic.swift` | Pure preferences logic (route saving, minute choices, import sanitizing) |

## Privacy

TrainTracker has no telemetry. Its only network traffic is to the unofficial third-party ÖBB API at `https://oebb.rolinek.at` (station search, journeys, journey refresh), which has no SLA. Your configuration is stored locally in `UserDefaults` (suite `traintracker`).

## License

MIT
