# Event-Driven Profile Cycle Follow-Up Read

Scenario: Basilisk V3 Pro connected over Bluetooth, Synapse closed. The user
set up profile 2 with a distinctive DPI table and reported that the physical
profile button cycles between all three onboard profiles. The active profile at
the start was profile 2.

Probe:

- `tools/python/bt_profile_cycle_watch_windows.py`
- Windows HID input via `hidapi`
- Windows BLE vendor GATT via `bleak`
- Paired BLE address: `FA:2E:1F:48:66:38`

## Pass 1: Three Presses

Output: `profile-cycle-event-driven-3press.json`

Baseline live DPI read (`0B 84 01 00`) returned:

```text
active_raw=5
stages=100,100,100,100,800
raw=050501640064000000026400640000000364006400000004640064000000052003200300
```

Each physical profile-button press produced the expected passive HID hint pair:

```text
04 04 00 00 00 00 00 00 00
05 05 39 00 00 00 00 00 00
```

The watcher issued exactly one `0B 84 01 00` read per debounced hint. Every
follow-up DPI read returned the same `100,100,100,100,800` table.

## Pass 2: One Press, Delayed Read, Button Fingerprint

Output: `profile-cycle-event-driven-delay-button-1press.json`

The watcher saw one passive HID hint pair, waited 2 seconds after the first
hint, then read:

- `0B 84 01 00`
- `08 84 01 04`

Both values stayed unchanged:

```text
0B 84 01 00 -> 050501640064000000026400640000000364006400000004640064000000052003200300
08 84 01 04 -> 04000101010104040000000000000000
```

## Candidate State Reads

A read-only sweep after the delayed pass also did not expose active
firmware-ring identity:

```text
01 86 00 00 -> 00 00 00
01 82 00 00 -> 00 00
01 8C 01 00 -> 01
01 8C 02 00 -> 01
01 8C 03 00 -> 01
01 8C 04 00 -> 01
01 8C 05 00 -> 01
```

## Interpretation

The passive HID hint is enough for event-driven change detection. OpenSnek does
not need to continuously poll just to notice the profile button.

The known live-target reads are not enough to identify the exact onboard
firmware-ring profile after Synapse-closed hardware cycling. They appear to
read the BLE live/software projection surface, which stayed pinned to the same
DPI table and button payload during these passes.

Implementation consequence:

- Use `04 04 ...` / `05 05 39 ...` as a reactive profile-change/stale hint.
- Run only bounded follow-up work after the hint.
- Do not present exact active onboard profile identity from `0B 84 01 00` or
  `08 84 01 04` until a firmware-ring active-slot read is mapped.
