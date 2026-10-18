# App validation follow-up (2026-10-18)

Contributor validated by device owner **@jpagh**, using the Naga V3 Pro's own
`1532:00E8` receiver and Mouse Dock Pro `1532:00A4` on macOS. These are owner
confirmations, not maintainer/local hardware validation.

## All Zones Off → Static regression

The owner reproduced a failure where selecting All Zones, then Off, then Static
relit only the scroll wheel and changed the picker to an individual zone.
Changing the color afterward reached every zone.

An AppState characterization test drove the editor actions and observed the
outgoing device patches. Before the correction it failed with zone
`scroll_wheel` and LED filter `[1]`, rather than `all` and an unfiltered patch.
The static-selection repair helper was treating `all` as invalid even after the
explicit picker-selection path had been corrected. It now preserves `all` and
only repairs stale zone IDs. Individual-zone static edits retain their LED filter.

After a clean app rebuild (`./run.sh --clean`), the owner confirmed that all three
zones relit and All Zones stayed selected. Concurrent read-only `0f:82` sampling
captured the transition below. Each entry is `effect-id:red/green/blue` for the
persistent layer; `00` is Off and `01` is Static. No identifying data is included.

```text
11:26:19  01=00:00/00/00  04=00:00/00/00  05=00:00/00/00
11:26:20  01=01:00/ff/00  04=01:00/ff/00  05=01:00/ff/00
11:26:21  01=01:00/ff/00  04=01:00/ff/00  05=01:00/ff/00
```

The three LED IDs are scroll wheel (`01`), logo (`04`), and 12-button side panel
(`05`). Sampling stopped before the idle/wake check so it did not keep the mouse
awake during that check.

## Owner-confirmed app checks

| Check | Result |
| --- | --- |
| V3 Pro front scroll-wheel button remapped through the app UI | Temporary keyboard action worked |
| Same button restored with Default through the app UI | Wheel-mode cycling returned |
| V3 Pro receiver unplug | App detected offline state |
| V3 Pro receiver replug and mouse movement | Controls recovered |
| Mouse Dock Pro unplug/replug | Removal and recovery worked; brightness remained readable |
| V3 Pro idle for approximately two minutes, then movement | No repeated Connected/Reconnecting flapping; wake passed |

The owner's Naga Pro (`0x0090`) media-key remaps were not changed during this
follow-up. The receiver checks above cover the V3 Pro's own dongle, not the dock's
receiver role or charging handoff. This finite idle check does not establish
long-duration reliability or Bluetooth behavior.

## Button-label follow-up

The owner requested physical, consistent front/rear names instead of factory-action
names or arbitrary numbering on unnumbered pairs. The agreed V3 Pro labels are:

| Slots | Labels |
| --- | --- |
| `11` / `12` | Index Button (front) / Index Button (rear) |
| `106` / `128` | Scroll Button (front) / Scroll Button (rear) |
| `5` / `4` | Panel Button (front) / Panel Button (rear) |

These are display-label changes only. Slot IDs, binding kinds, factory blocks,
and Default restore behavior are unchanged. Numbered 6-/12-button plate labels
remain numbered. Position-to-slot evidence is in the original capture README.
