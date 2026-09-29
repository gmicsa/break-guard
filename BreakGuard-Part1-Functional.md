# BreakGuard — Functional Requirements

---

## 1. Overview

BreakGuard is a macOS menu bar app that tracks continuous work time since the last screen unlock, reminds the user to take breaks via notifications and sounds, and records daily session history for review. It lives exclusively in the menu bar — no Dock icon.

---

## 2. Core Behaviour

### Session lifecycle

- A **work session** starts when the screen is unlocked and ends when it is locked.
- A **break session** is the period between a lock and the next unlock.
- Both session types are recorded automatically with no user action required.
- If the app is quit mid-session, the partial work session is saved.
- Sessions that span midnight are split into two records at the midnight boundary.

### Break reminder flow

The default thresholds are 60 minutes for the first alert and 5-minute intervals for repeats, but all values are user-configurable (see Settings).

```
t=0:00   Unlock  ->  work timer starts (green)
t=1:00   Info notification + sound  ->  "Time for a break!"
t=1:05   Warning #1 + sound  ->  "Still working?"
t=1:10   Warning #2 + sound
  ...
t=1:30   Warning #6 + sound  ->  warnings stop, label stays red
[lock]   Session saved, timer resets
```

### Snooze

When a warning fires, the user can snooze (10 min default). During snooze the work timer keeps running — only the warning repeat is paused. When snooze expires, warnings resume.

---

## 3. Menu Bar Label

The menu bar button shows the current work time as `HH:MM`. The appearance changes by state:

| State | Display | Color |
|---|---|---|
| Locked | `☕ --:--` | Gray |
| Working | `🟢 HH:MM` | Green |
| Warned | `🔴 HH:MM` | Red |
| Snoozed | `🟠 HH:MM` | Orange |

---

## 4. Menu Items

```
BreakGuard
-----------------------------------------
⚠️ Notifications disabled  (shown only if notification permission denied; opens System Settings > Notifications)
-----------------------------------------
Working for 1:23          (dynamic, gray, disabled)
-----------------------------------------
Snooze 10 min             (enabled only when state = Warned and warningsFired < maxWarnings)
-----------------------------------------
View Stats...
-----------------------------------------
Settings  >
    Work threshold  >
        o 45 minutes
        * 60 minutes      (* = active)
        o 90 minutes
        o Custom...
    Warning interval  >
        * 5 minutes
        o 10 minutes
        o Custom...
    Warning count  >
        o 4  (20 min)
        * 6  (30 min)
        o 12 (60 min)
        o Custom...
    Snooze duration  >
        o 5 minutes
        * 10 minutes
        o 15 minutes
        o Custom...
    -----------------
    Sounds  >
        [x] Enable sounds
        -----------------
        Info sound  >       (14 system sounds, click to preview)
        Warning sound  >    (14 system sounds, click to preview)
    -----------------
    [x] Launch at login
-----------------------------------------
Quit BreakGuard
```

Custom... items open a small input dialog. Input must be a whole number greater than 0 and within the allowed range; invalid input shows an error.

### Custom input upper bounds

| Setting | Min | Max |
|---|---|---|
| Work threshold | 1 min | 480 min |
| Warning interval | 1 min | 120 min (and ≤ work threshold) |
| Warning count | 1 | 99 |
| Snooze duration | 1 min | 120 min |

---

## 5. Notifications

| Trigger | Title | Body |
|---|---|---|
| Work threshold reached | "Time for a break! ☕" | "You've been working for N minutes. Step away and rest." |
| Each repeat warning | "Still working? 🔴" | "You've been at it for N minutes. Your body needs a break." |
| Snooze expires | "Snooze over 🔔" | "Break reminder is back. Consider stepping away now." |

- Warnings include a **Snooze** action button directly on the notification.
- Notifications are shown even when the app is in the foreground (it is always foreground as a menu bar app).
- Sound is played separately via the app for full control (system notification sound is disabled).

---

## 6. Sounds

- Two configurable sounds: one for the info notification, one for warnings.
- Master on/off toggle.
- Clicking a sound name in the Settings menu plays it as a preview.
- Available sounds: Basso, Blow, Bottle, Frog, Funk, Glass (default info), Hero, Morse, Ping, Pop, Purr, Sosumi (default warning), Submarine, Tink.

---

## 7. User-Configurable Settings

| Setting | Default | Options |
|---|---|---|
| Work threshold | 60 min | 45, 60, 90, or custom |
| Warning interval | 5 min | 5, 10, or custom |
| Warning count (repeats) | 6 | 4, 6, 12, or custom |
| Snooze duration | 10 min | 5, 10, 15, or custom |
| Sound enabled | On | Toggle |
| Info sound | Glass | Any of 14 system sounds |
| Warning sound | Sosumi | Any of 14 system sounds |
| Launch at login | Off | Toggle |

All settings persist across app restarts.

---

## 8. Stats Window

Opened via "View Stats..." in the menu. Floating panel, non-modal. Only one instance — reopening brings it to front.

### Today summary

Shows total work time and total break time for the current day as large readable values:

```
TODAY — Thursday, March 20
+----------------------------------------------------------+
|  🟢 Total Work    4h 32m        🔵 Total Break    1h 10m |
+----------------------------------------------------------+
```

### Session log table

A scrollable table of all sessions for today, in chronological order:

| Type | Start | End | Duration |
|---|---|---|---|
| 🟢 Work | 08:32 | 10:15 | 1h 43m |
| 🔵 Break | 10:15 | 10:28 | 13m |
| 🟢 Work | 10:28 | 12:44 | 2h 16m |
| 🔵 Break | 12:44 | 13:17 | 33m |
| 🟢 Work | 13:17 | ongoing | - |

### 7-day bar chart

Shows the last 7 calendar days. For each day there are two side-by-side bars: work (green) and break (blue). The total time is labelled above each pair and the day name below. A legend is shown bottom-right.

---

## 9. Data Storage

- One JSON file per calendar day, stored in `~/Library/Application Support/BreakGuard/`.
- File naming: `stats-YYYY-MM-DD.json`
- Each file contains an array of session records with type (`work` or `break`), start time, end time, and duration.
- If a file is corrupt on load, it is renamed to `.bak.json` and a fresh file is started.
- Break sessions shorter than 5 seconds (e.g. accidental lock) are ignored. The lock/unlock debounce (1.5 s) is separate from this threshold.
- All timestamps are stored as ISO 8601 UTC. All display formatting uses the user's local timezone.

---

## 10. Edge Cases

| Scenario | Behaviour |
|---|---|
| App launched while screen already unlocked | Starts working immediately; timer starts at 0 from launch time (initial period not recorded as a break) |
| Machine sleeps without explicit lock | Treated as a lock event |
| App quit mid-session | Partial work session is saved on quit |
| Session spans midnight | Split into two records at midnight |
| Lock/unlock fires multiple times rapidly | Debounced with a 1.5-second guard |
| maxWarnings reached, user still working | Label stays red; no more sound or notifications |

---

## 11. Out of Scope

- iCloud sync
- Multiple macOS user accounts
- iOS / iPadOS version
- Idle detection (keyboard/mouse inactivity)
- Calendar app integration
