# TrainTracker — Notifications Design Spec

_2026-05-26_

## Goal

Add macOS push notifications for three events: departure reminder, significant delay, and platform change. Settings (enabled/threshold) are configurable in the Preferences panel.

## New Files

- `Sources/TrainTracker/NotificationManager.swift` — all notification logic

## Modified Files

- `Sources/TrainTracker/AppConfig.swift` — add `NotificationSettings` struct + field
- `Sources/TrainTracker/PreferencesWindowController.swift` — add Notifications section
- `Sources/TrainTracker/StatusBarController.swift` — wire `NotificationManager.process` into `refresh()`
- `Tests/TrainTrackerTests/NotificationManagerTests.swift` — unit tests

---

## Section 1: Data Model

Add to `AppConfig.swift`:

```swift
struct NotificationSettings: Codable {
    var departureReminderEnabled: Bool  = true
    var departureReminderMinutes: Int   = 10
    var delayAlertEnabled: Bool         = true
    var delayAlertThresholdMinutes: Int = 10
    var platformChangeEnabled: Bool     = true
}
```

Add to `AppConfig`:

```swift
var notifications: NotificationSettings = NotificationSettings()
```

Backwards-compatible: existing stored configs missing the key decode to all-defaults.

---

## Section 2: NotificationManager

`NotificationManager` is a `@MainActor final class`. It has no public state — only one public method and one reset path.

### Authorization

On first call to `process`, request `UNUserNotificationCenter` authorization for `.alert + .sound` (async, fire-and-forget). Does not block. If the user denies, `UNUserNotificationCenter.add` calls silently fail.

### State

```swift
private var lastDelaySecs: Int = 0
private var lastDeparturePlatform: String? = nil
private var lastArrivalPlatform: String? = nil
private var departureReminderSentFor: String? = nil  // "trainName|ISO8601plannedDeparture"
private var trackedTrainKey: String? = nil           // same format; reset state when it changes
```

### Public API

```swift
func process(_ data: TrainData, settings: NotificationSettings)
```

### Logic

**Reset guard:** compute `key = "\(data.trainName)|\(data.scheduledDeparture)"`. If `key != trackedTrainKey`, reset all state fields and update `trackedTrainKey`.

**Departure reminder:**
- Guard: `settings.departureReminderEnabled && !data.isEnRoute`
- Guard: `departureReminderSentFor != key`
- Compute `rtDep = data.scheduledDeparture + data.departureDelaySecs`
- Guard: `rtDep.timeIntervalSinceNow <= Double(settings.departureReminderMinutes * 60)`
- Guard: `rtDep.timeIntervalSinceNow > 0` (hasn't departed yet)
- Post notification: "🚂 WB 912 departs in Xm" + platform in body if available
- Set `departureReminderSentFor = key`

**Delay alert:**
- Guard: `settings.delayAlertEnabled`
- Let `threshold = settings.delayAlertThresholdMinutes * 60`
- Guard: `data.arrivalDelaySecs >= threshold && lastDelaySecs < threshold`
- Post: "WB 912 is now +Xm late"
- Always update `lastDelaySecs = data.arrivalDelaySecs`

**Platform change:**
- Guard: `settings.platformChangeEnabled`
- For departure platform: if `lastDeparturePlatform != nil && data.departurePlatform != lastDeparturePlatform`
  - Post: "WB 912: departure platform changed to X"
- Always update `lastDeparturePlatform = data.departurePlatform`
- Same for `arrivalPlatform`

### Notification construction

Use `UNMutableNotificationContent` with `.title` and `.body`. Trigger: `UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)` (fires immediately). Each notification gets a stable `identifier` so duplicates are replaced, not stacked:
- departure: `"departure-\(key)"`
- delay: `"delay-\(key)"`
- dep-platform: `"platform-dep-\(key)"`
- arr-platform: `"platform-arr-\(key)"`

---

## Section 3: Preferences Panel

Panel height increases from 320pt to 490pt.

New section appended below the saved routes table (y-coordinates shift up accordingly or panel grows down):

```
Notifications                          ← section label, y=~130
──────────────────────────────────────
[✓] Departure reminder  [10] minutes before    ← y=~108
[✓] Delay alert when    [10]+ minutes late     ← y=~80
[✓] Platform change alert                      ← y=~52
```

Controls:
- 3× `NSButton(checkboxWithTitle:)` 
- 2× `NSTextField` (number input, width 40pt, `formatter: NumberFormatter` integers only, range 1–120)
- Number fields disabled when their checkbox is unchecked

New state in `PreferencesWindowController`:
```swift
private var pendingNotifications: NotificationSettings = NotificationSettings()
```
Loaded from `AppConfigStore.shared.load().notifications` in `loadCurrentConfig()`.

`saveAndClose()` reads checkbox/field values into `pendingNotifications` and writes to `config.notifications` before saving.

---

## Section 4: Wiring

`StatusBarController` adds:

```swift
private let notificationManager = NotificationManager()
```

In `refresh()`, after the `switch status` that sets `displayStatus`:

```swift
if case .tracking(let td, _) = displayStatus {
    notificationManager.process(td, settings: config.notifications)
}
```

`config` is already loaded at the top of `refresh()` — no extra read needed.

---

## Testing

`NotificationManagerTests.swift` covers:

- Departure reminder fires when within window, not sent again on next call
- Departure reminder does not fire when train is already en route
- Departure reminder does not fire when outside window
- Delay alert fires when crossing threshold (29m → 31m with 30m threshold)
- Delay alert does not fire again when already above threshold (31m → 35m)
- Platform change fires when departure platform changes from known value
- Platform change does not fire on first observation (no previous value)
- State resets when a different train is processed
- All guards respect their `enabled` flag

For testability, `NotificationManager` accepts a `NotificationScheduler` protocol (one method: `add(_ request: UNNotificationRequest)`) in its initializer, defaulting to `UNUserNotificationCenter.current()`. Tests inject a spy that records posted identifiers and content, without touching the real notification system.

---

## Out of Scope

- "Train arrived" notification (excluded by user)
- Notification history / in-app inbox
- Per-route notification settings
- Snooze / "remind me again in Xm"
