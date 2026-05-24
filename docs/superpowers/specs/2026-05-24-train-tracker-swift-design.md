# TrainTracker Swift — Design Spec

_2026-05-24_

## Problem

The existing Rust/xbar implementation has two persistent failures:

- **Station not found (A):** The app stores station _names_ and re-resolves them to IDs on every launch by taking the first search result. If the first result is wrong, all journey searches fail silently.
- **Train missing (B):** The train pick list sometimes omits the user's train. Root causes: the hardcoded station list in the menu doesn't always match the API's expected spelling, and the `journeys_to_train_options` filter removes trains whose arrival time has passed (so a train boarded mid-journey disappears from the pick list).

The API itself (`oebb.macistry.com/api`) is correct — WB 912 Linz → Salzburg appeared reliably in the -2h offset search during live testing. The data is there; the client usage is wrong.

## Goal

A native macOS menu bar app in Swift that:

- Tracks a selected Austrian train (OeBB, Westbahn, etc.) on a configured route
- Shows countdown to arrival in the menu bar title, with delay info
- Lets the user quickly switch trains on the same route without reconfiguring stations
- Has a native look — plain text, no emojis, standard AppKit controls
- Requires no third-party dependencies

## API

**Base URL:** `https://oebb.macistry.com/api`

Two endpoints:

```
GET /locations?query=<text>&results=8
  Returns: array of stops/stations with id and name
  Used: in Preferences panel for live station search

GET /journeys?from=<id>&to=<id>&departure=<iso8601>&results=12&stopovers=true
  Returns: journeys array with legs, delays, stopovers
  Used: 4 concurrent calls at offsets -6h, -4h, -2h, now to build the full train list
```

**Key fix for A:** Station IDs are resolved once in the Preferences panel (user picks from live search results) and stored permanently. The fetcher never does a name→ID lookup at runtime.

**Key fix for B:** The train pick list is built from all 4 time-window searches combined, with no filter on arrival time (a train that has already arrived still appears so the user can select it mid-journey). Deduplication is by `trainNumber + plannedDeparture` (exact string match, not fuzzy).

## Architecture

Six Swift files, zero third-party dependencies (URLSession + AppKit only):

```
TrainTracker/
  AppDelegate.swift                  — NSApplication entry, LSUIElement = YES (no dock icon)
  StatusBarController.swift          — NSStatusItem + NSMenu, 30s refresh timer
  PreferencesWindowController.swift  — NSPanel for station setup and saved routes
  OeBBClient.swift                   — URLSession wrapper for /locations and /journeys
  TrainFetcher.swift                 — Business logic: fetch journeys, deduplicate, match train
  AppConfig.swift                    — Codable config, UserDefaults persistence
  Models.swift                       — Codable API response types + internal display types
```

Data flow:

```
StatusBarController
  → Timer fires every 30s (or on manual Refresh)
  → TrainFetcher.fetch(config:)
      → OeBBClient.journeys(from:to:departure:) × 4 concurrent (async/await)
        offsets: -6h, -4h, -2h, now
      → deduplicates + filters
      → returns TrainStatus
  → StatusBarController rebuilds NSMenu and updates title string
```

The PreferencesWindowController is independent: it calls `OeBBClient.searchStations(query:)` directly as the user types, writes the chosen station ID to `AppConfig`, and triggers an immediate refresh on close.

## Internal Models

```swift
enum TrainStatus {
    case noConfig                   // no stations configured yet
    case pickTrain([TrainOption])   // stations set, user hasn't picked a train
    case tracking(TrainData)        // train selected, live data available
    case error(String)
}

struct TrainData {
    var trainName: String
    var fromName: String
    var toName: String
    var scheduledDeparture: Date
    var scheduledArrival: Date
    var departureDelaySecs: Int
    var arrivalDelaySecs: Int
    var departurePlatform: String?
    var arrivalPlatform: String?
    var stopovers: [StopoverInfo]
    var isEnRoute: Bool
}

struct StopoverInfo {
    var name: String
    var scheduledArrival: Date?
    var arrivalDelaySecs: Int
    var passed: Bool
    var isNext: Bool
}

struct TrainOption {
    var name: String
    var scheduledDeparture: Date
    var scheduledArrival: Date
    var departureDelaySecs: Int
}
```

## Config & Persistence

Stored in `UserDefaults` suite `"traintracker"` as a single JSON-encoded `AppConfig`:

```swift
struct AppConfig: Codable {
    struct Station: Codable {
        var name: String   // display only
        var id: String     // used for all API calls
    }
    struct SavedRoute: Codable {
        var from: Station
        var to: Station
    }

    var fromStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var savedRoutes: [SavedRoute]
}
```

- First launch: `fromStation`/`toStation` nil → menu shows "Open Preferences to get started"
- Picking a train writes `trainNumber` immediately, triggers refresh
- Loading a saved route clears `trainNumber` so the Switch Train list appears fresh

## Menu Bar UI

**Title strings (no emojis):**

| State | Title |
|---|---|
| Waiting to depart | `WB 912  in 12m` |
| En route, delayed | `WB 912 arr 14:08 +3m` |
| En route, on time | `WB 912 arr 14:08` |
| Arrived | `WB 912  Arrived` |
| No config | `Train` |
| Error | `Train (!)` |

**Menu when tracking:**

```
WB 912  Linz/Donau Hbf → Salzburg Hbf
Dep: 12:56   Arr: 14:08 +3m
Platform: 3 → 5
─────────────────────────────
  Attnang-Puchheim  13:28        ← passed (disabled, greyed via NSMenuItem.isEnabled = false)
  Vöcklabruck       13:38  *     ← next stop (asterisk or indented marker)
  Straßwalchen      13:50
─────────────────────────────
Switch Train…                    ← submenu: trains on configured route
─────────────────────────────
Preferences…
Refresh
Quit
```

Passed stopovers are shown as disabled menu items (greyed out automatically by AppKit). The next stop gets a leading `>` prefix. Future stops are normal disabled items (informational only — no stops are clickable).

## Preferences Panel

Fixed-size `NSPanel` (~380×280pt), non-resizable, opens centered:

```
┌─────────────────────────────────────────┐
│  Train Tracker                          │
│                                         │
│  From   [Linz/Donau Hbf          ][...] │
│  To     [Salzburg Hbf            ][...] │
│                                         │
│  ┌─ Search results ──────────────────┐  │
│  │ Linz/Donau Hbf                   │  │
│  │ Linz Ost                         │  │
│  │ Linz/Donau Vbf (Busterminal)     │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Saved routes:                          │
│  Linz/Donau Hbf → Salzburg Hbf  [Load] │
│                                         │
│                          [Save & Close] │
└─────────────────────────────────────────┘
```

- Clicking `[...]` makes that field active; typing triggers a 300ms debounced `/locations` search
- Clicking a result sets the station (name + ID stored)
- `[Save & Close]` writes to `UserDefaults` and triggers an immediate refresh
- "Saved routes" are populated automatically when both stations are set and the user saves

## Error Handling

| Failure | Behaviour |
|---|---|
| Network error | Show last known data; title shows `(!)` after 2 failed refreshes |
| No journeys returned | Keep last known data; retry on next 30s tick |
| Train number not found in results | Show "WB 912 not found — Switch Train to reselect" in menu |
| Station ID missing (first launch) | Menu shows "Open Preferences to get started" |

No crash on decode failure — all API response parsing uses optional chaining; a malformed response is treated as an empty result.

## Out of Scope

- Via/connection (two-leg journey) mode — not implemented in v1; add later if needed
- GPS-based auto-detection
- Notifications / alerts for delays
- Custom station IDs (all stations come from the API search)
