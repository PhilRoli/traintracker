# TrainTracker Improvements Design
**Date:** 2026-05-26

## Overview

Three focused improvements to the existing Swift menu bar app:

1. **Smarter real-time tracking** — use the journey refresh token to replace the 5-request batch with a single API call on repeat refreshes
2. **Switch Route… submenu** — surface saved routes directly in the menu bar for one-click route switching
3. **Delete saved routes** — add a "–" button and Delete key support to the saved routes table in Preferences

---

## Feature 1: Journey Refresh Token

### Problem
Every 30-second tick fires 5 concurrent `/journeys` requests (covering −6h to now). Once a train is identified, all subsequent refreshes still do this full batch — wasteful and slow.

### Solution
The FPTF-style API returns a `refreshToken` field on each `APIJourney` object. After fetching and identifying the tracked train, store its `refreshToken` in `TrainFetcher`. On the next `fetch()` call, if a token is present, call `GET /journeys/{ref}?stopovers=true` instead of the 5-request batch. Fall back to the full batch on any error.

### Data model change
`APIJourney` gains:
```swift
let refreshToken: String?
```

### New client method
`OeBBClient` gains:
- `static func refreshJourneyURL(token: String) -> URL?` — builds `…/journeys/{token}?stopovers=true`
- `func refreshJourney(token: String) async throws -> APIJourney`

### TrainFetcher changes
- New private `var cachedRefreshToken: String?`
- In `fetch(config:)`: if `cachedRefreshToken` is non-nil, attempt `refreshJourney(token:)` first; on success extract the matching leg and return `.tracking`. On any failure, clear the token and fall back to `fetchAllJourneys`.
- After a successful full fetch that identifies the tracked train, store its journey's `refreshToken`.
- Token is cleared whenever the user switches train or route (config change detected in `fetch(config:)`).

### Error handling
| Scenario | Behaviour |
|---|---|
| Token nil or empty | Skip refresh path; do full fetch |
| 4xx / 5xx / timeout | Clear token; fall back to full fetch |
| Train already arrived (journey gone) | Full fetch returns nothing; existing `.error` path shown |

---

## Feature 2: Switch Route… Submenu

### Problem
Switching between saved routes requires opening Preferences, which is slow.

### Solution
Add a "Switch Route…" submenu in the menu bar (placed after "Switch Train…"), populated from `AppConfigStore.shared.load().savedRoutes`. Selecting a route sets `fromStation`, `toStation`, clears `trainNumber`, saves the config, and triggers a refresh.

Also: the Preferences saved-routes table currently has a separate "Load" column. Since clicking a row already populates the from/to fields, the "Load" column is redundant — drop it as part of this change (table becomes single-column).

### Menu structure
```
Switch Train…  ▶  [train options]
Switch Route…  ▶  Wien Hbf → Linz Hbf  ✓
                  Linz Hbf → Salzburg Hbf
               ── (or: "No saved routes" disabled)
```
The active route (matching current `fromStation`/`toStation`) shows a checkmark.

### StatusBarController changes
- New `@objc func selectRoute(_ sender: NSMenuItem)` action: reads `SavedRoute` from `representedObject`, updates config, calls `refresh()`
- `buildMenu(for:)` extended to add the submenu after "Switch Train…" in the `.tracking` and `.pickTrain` cases
- Helper `addRouteOptions(_:to:currentRoute:)` mirrors existing `addTrainOptions`

### Edge cases
- No saved routes → disabled "No saved routes" item in submenu
- Switching route clears `trainNumber` → app enters `.pickTrain` state

---

## Feature 3: Delete Saved Routes

### Problem
There is no way to remove a saved route from Preferences — the list only grows.

### Solution
Standard macOS table pattern: a "–" button below the saved routes table, plus Delete key support when a row is selected.

Deletion is staged: it updates the in-memory `savedRoutes` array and reloads the table immediately, but is only persisted when the user clicks "Save & Close" (consistent with how adding a route works).

### PreferencesWindowController changes
- Drop the "load" `NSTableColumn`; table becomes single-column (route name only)
- Add a `deleteRouteButton: NSButton` (title "–") below the saved routes table; enabled only when `savedRoutesTable.selectedRow >= 0`
- `savedRoutesTable.delegate` selection-change callback enables/disables the button
- `@objc func deleteSelectedRoute()` removes `savedRoutes[selectedRow]`, reloads table
- Override `keyDown` on the table view (via a subclass or `NSTableViewDelegate`) to call `deleteSelectedRoute()` on Delete/Backspace

### Edge cases
- Deleting the active route → only affects the saved list; active `fromStation`/`toStation` in config is unchanged
- Deleting last route → table empty, "–" button disabled
- No confirmation dialog (consistent with rest of the UI)

---

## File Change Summary

| File | Changes |
|---|---|
| `Models.swift` | Add `refreshToken: String?` to `APIJourney` |
| `OeBBClient.swift` | Add `refreshJourneyURL(token:)` + `refreshJourney(token:)` |
| `TrainFetcher.swift` | Cache refresh token; try single-call refresh before full batch |
| `StatusBarController.swift` | Add "Switch Route…" submenu + `selectRoute(_:)` action |
| `PreferencesWindowController.swift` | Drop "Load" column; add "–" button + Delete key for saved routes |

---

## Testing

### TrainFetcherTests (new cases)
- `testRefreshTokenCachedAfterFullFetch` — token stored after successful full fetch with tracked train
- `testRefreshPathUsedWhenTokenPresent` — mock client; verify only `refreshJourney` called, not `fetchJourneys`
- `testFallsBackToFullFetchOnRefreshError` — mock `refreshJourney` throws; verify `fetchJourneys` called and token cleared

### OeBBClientTests (new case)
- `testRefreshJourneyURL` — verify URL shape: `.../journeys/{token}?stopovers=true`

### StatusBarControllerTests (extended)
- `buildMenu` tests extended to cover Switch Route submenu: routes present (with active-route checkmark), no routes (disabled item)

### Manual
- Preferences delete: "–" button and Delete key remove routes; deletion not persisted until "Save & Close"
- Switch Route: selecting a route from the submenu updates the menu bar and clears the train selection
