# Device Support Matrix

This page is the shipped OpenSnek support matrix by device and transport.

This pass is derived from the implementation, not just protocol notes:
- device/profile metadata: [`OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift`](../OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift)
- USB state + writes: [`OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+USB.swift`](../OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+USB.swift)
- Bluetooth state + writes: [`OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+Bluetooth.swift`](../OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+Bluetooth.swift)
- UI exposure and feature gating: [`OpenSnek/Sources/OpenSnek/UI/DeviceDetailView.swift`](../OpenSnek/Sources/OpenSnek/UI/DeviceDetailView.swift) and [`OpenSnek/Sources/OpenSnek/Services/EditorStore.swift`](../OpenSnek/Sources/OpenSnek/Services/EditorStore.swift)

This matrix tracks shipped hardware-facing support. Internal editor/workspace plumbing does not count as shipped device support unless the hardware behavior is actually exposed and supported in the app.

Use [docs/protocol/PARITY.md](./protocol/PARITY.md) for lower-level reverse-engineering notes and capture-backed protocol gaps.

## Status Key

Overall transport status:
- `Validated`: the shipped profile is locally validated in `DeviceSupport.swift`
- `Contributor validated`: the shipped profile is based on external contributor hardware validation and has not been locally validated by OpenSnek maintainers
- `Mapped`: the shipped profile exists, but the profile metadata is still marked unvalidated
- `Not shipped`: the hardware transport may exist, but OpenSnek does not claim support for it yet
- `No transport`: that device does not offer that transport

Feature rows:
- `Shipped`: implemented in the backend and surfaced by the current app for that device/transport
- `Contributor validated`: implemented based on contributor-validated hardware behavior, but not locally validated by OpenSnek maintainers
- `Limited`: shipped, but with reduced scope such as static-only lighting or documented read-only button slots
- `Mapped`: comes from a shipped but still unvalidated mapped profile
- `Not shipped`: the app intentionally does not claim or expose this hardware feature as supported yet
- `Hidden`: the current bridge/UI does not surface that feature on this transport
- `Scalar only`: the profile does not ship independent X/Y DPI editing
- `Single slot`: no multi-slot onboard button-profile workflow exists for that device/transport

Button remap keyboard actions support modifier chords on shipped USB and Bluetooth profiles through the shared `modifier byte + HID key` function block.

## Quick Summary

| Device | USB | BT | Biggest Gaps |
|---|---|---|---|
| Basilisk V3 X HyperSpeed | `Validated` | `Validated` | Bluetooth keeps lighting to static color, hides poll-rate and threshold controls, and leaves the Hypershift/sniper path read-only |
| Basilisk V3 | `Mapped` | `No transport` | Shares the Basilisk V3 USB family configuration, but remains unvalidated on local hardware |
| Basilisk V3 Pro | `Validated` | `Validated` | Ships mapped onboard profile CRUD on USB and Bluetooth; Bluetooth keeps lighting static-only, hides poll-rate and threshold controls, and does not ship clutch/profile-button remap |
| Basilisk V3 35K | `Validated` | `No transport` | Shares the Basilisk V3 USB family configuration with mapped onboard profile CRUD; no Bluetooth transport |
| Basilisk V3 Pro 35K Phantom Green Edition | `Not shipped` | `Contributor validated` | Bluetooth reuses the Basilisk V3 Pro vendor keys with a `35,000` DPI ceiling and two lighting zones (no logo LED); profile CRUD stays hidden because the device rejects metadata reads, and live changes reset on power cycle |
| Orochi V2 | `Not shipped` | `Contributor validated` | Contributor validated Bluetooth DPI stages, battery, and no-RGB behavior; button remap is profile-mapped pending hardware readback validation |
| Naga Pro | `Contributor validated` | `Contributor validated` | Core controls and known-safe side-panel slots ship with captured native defaults; all three side panels have been physically press-validated (12- and 6-button in PR #121, 2-button in the 2026-10-17 capture addendum), and the shipped slot table was cross-checked against the device's own mappable-button inventory |
| Naga V2 Pro | `Contributor validated` | `Contributor validated` | Wired `0x00A7`, 2.4 GHz receiver `0x00A8`, and Bluetooth `0x00A9` share DPI stages, battery, side-panel remapping, and logo + 12-button side-panel lighting; side-panel label order is press-validated, the bottom button is remappable, and the two top DPI buttons stay preserved read-only |
| Naga V3 Pro | `Contributor validated` | `Contributor validated` | Wired USB `0x00E7`, 2.4 GHz receiver `0x00E8`, and Bluetooth `0x00E9`; ships DPI up to the published `50,000` ceiling with independent X/Y, three lighting zones (scroll wheel, logo, side panel), the full 2/6/12-button plate slot table, and press-validated body buttons including both scroll-wheel buttons. Onboard profile CRUD stays hidden because the device rejects metadata reads, and the wheel's tactile/free-spin/smart-reel mode has no readout, so it is only changeable with the front scroll button's factory action |
| Basilisk (2017) | `Contributor validated` | `No transport` | Contributor validated DPI (scalar, independent X/Y, live 5-stage table), poll-rate reads, and logo/scroll lighting with restore-verified writes; button remap and onboard profiles are not mapped |
| Lancehead Tournament Edition | `Contributor validated` | `No transport` | Contributor validated DPI (scalar, independent X/Y, live 5-stage table read without OpenRazer's `0xFF` stage transaction), poll-rate reads, and all four lighting zones; button remap is not mapped |
| Huntsman Mini | `Contributor validated` | `No transport` | Keyboard: contributor validated backlight lighting, brightness, and that poll-rate reads return `status 0x05` (unsupported). No DPI hardware; key remap is not mapped |
| Tartarus Pro | `Contributor validated` | `No transport` | Keypad: contributor validated backlight lighting and brightness (LED `0x00` and `0x05` alias the same register). Analog actuation and key remap have no public protocol; OpenSnek never switches this device into driver mode |
| Mouse Dock | `Contributor validated` | `No transport` | Accessory: contributor validated single logo-LED static color, brightness, and spectrum/pulse writes over USB. No DPI, buttons, battery, or onboard profiles |
| Mouse Dock Pro | `Contributor validated` | `No transport` | Accessory: contributor validated logo-LED brightness, static color, wave, spectrum, and breathing writes over USB, with working brightness telemetry. Answers only transaction ID `0xFF` and reads brightness at LED `0x0F` instead of the `0x00` write address; per-cell custom-frame mapping is still unmapped |

## Basilisk V3 USB Family Assumptions

For future USB feature work, treat the wired Basilisk V3 (`0x0099`), Basilisk V3 Pro (`0x00AA`/`0x00AB`), and Basilisk V3 35K (`0x00CB`) as one shared Basilisk V3 USB family unless hardware validation proves a device-specific exception.

- USB lighting effect work should start from the assumption that all three share the same `0x0F` zone-effect set and the same three public zones: scroll wheel `0x01`, logo `0x04`, and underglow `0x0A`.
- USB onboard-profile work uses the same mapped core profile API shape documented in [USB_PROFILE_CRUD_SPEC.md](./protocol/USB_PROFILE_CRUD_SPEC.md) across the family; keep device-specific exceptions out of the implementation unless hardware validation proves one.
- The Basilisk V3 X HyperSpeed is not part of this family assumption; it has its own simpler USB/Bluetooth profile shape.

## Basilisk V3 X HyperSpeed

USB PID `0x00B9`, Bluetooth PID `0x00BA`

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Validated` | `Validated` | Both transports ship today |
| DPI stages + active stage | `Shipped` | `Shipped` | Bluetooth state comes from `readBluetoothState()` plus the passive DPI tracker |
| Independent X/Y DPI | `Scalar only` | `Scalar only` | This profile ships scalar DPI only because `supportsIndependentXYDPI` is false on both transports |
| Poll rate | `Shipped` | `Hidden` | USB uses the shared `getPollRate` / `setPollRate` path; Bluetooth state hard-codes `poll_rate: nil` and `capabilities.poll_rate: false` |
| Sleep timeout | `Shipped` | `Shipped` | USB reads `getIdleTime`; Bluetooth reads `powerTimeoutGet` and exposes the power-management card |
| Low battery threshold | `Shipped` | `Hidden` | USB reads `getLowBatteryThreshold`; Bluetooth never puts a threshold value into `MouseState`, so the UI never renders the threshold card |
| Battery telemetry | `Shipped` | `Shipped` | Bluetooth uses vendor battery reads; the AA-powered BT path intentionally reports `charging = false` |
| Lighting: brightness + static color | `Shipped` | `Shipped` | The profile ships one lighting zone (`0x01`) on both transports |
| Lighting: extra effects | `Shipped` | `Limited` | USB exposes `off`, `static`, `spectrum`, `wave`, `reactive`, `pulseSingle`, `pulseDual`, and `pulseRandom`; Bluetooth is static-only because the BT profile advertises only `.staticColor` |
| Button remap: shipped editable slots | `Shipped` | `Shipped` | USB and BT writable slots are `1-5`, `9`, `10`, and `96` from the profile metadata |
| Button remap: unsupported slots | `Shipped` | `Hidden` | USB has no extra unsupported slots documented on this profile; Bluetooth slot `6` Hypershift/sniper is not surfaced as a control and only appears in the unsupported-buttons footnote |
| Scroll controls | `Shipped` | `Hidden` | USB has shared `get/setScrollMode`, `get/setScrollAcceleration`, and `get/setScrollSmartReel`; Bluetooth never populates those state fields and the UI excludes BT scroll controls |
| Onboard hardware profiles | `Single slot` | `Single slot` | Both transports ship with `onboardProfileCount = 1`, so there is no hardware multi-profile surface to expose here |

## Basilisk V3

USB PID `0x0099`, no Bluetooth transport

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Mapped` | `No transport` | The shipped USB profile is derived from OpenRazer plus the 35K layout, not yet locally validated in OpenSnek |
| DPI stages + active stage | `Mapped` | `No transport` | The mapped USB profile clamps DPI to `26,000` |
| Independent X/Y DPI | `Mapped` | `No transport` | The mapped V3 USB profile inherits the shared Basilisk V3 USB family independent X/Y DPI configuration |
| Poll rate | `Mapped` | `No transport` | Uses the shared USB poll-rate read/write path through the mapped profile |
| Sleep timeout | `Mapped` | `No transport` | Uses the shared USB idle-time path through the mapped profile |
| Low battery threshold | `Mapped` | `No transport` | Uses the shared USB threshold path through the mapped profile |
| Battery telemetry | `Mapped` | `No transport` | Uses the shared USB battery path through the mapped profile |
| Lighting: brightness + static color | `Mapped` | `No transport` | The mapped profile ships the shared Basilisk V3 USB family zones: `0x01`, `0x04`, and `0x0A` |
| Lighting: extra effects | `Mapped` | `No transport` | The mapped USB profile advertises the shared Basilisk V3 USB family set: `off`, `static`, `spectrum`, and `wave` |
| Button remap: shipped editable slots | `Mapped` | `No transport` | The mapped USB profile exposes writable slots `1-5`, `9`, `10`, `15`, `52`, `53`, and `96` |
| Button remap: unsupported slots | `Hidden` | `No transport` | The mapped profile documents slot `14` and slot `106` as unsupported footnote entries rather than editable controls |
| Scroll controls | `Mapped` | `No transport` | The mapped profile rides the same shared USB scroll-control implementation as the other USB Basilisk profiles |
| Onboard hardware profiles | `Mapped` | `No transport` | The mapped V3 USB profile exposes the shared inventory-backed core profile CRUD surface: list, read, create, rename, update, delete/unassign, activate, and passive profile-cycle refresh |

## Basilisk V3 Pro

USB PIDs `0x00AA` / `0x00AB`, Bluetooth PID `0x00AC`

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Validated` | `Validated` | Both transports ship today |
| DPI stages + active stage | `Shipped` | `Shipped` | USB and BT both ship stage editing; the BT path also feeds passive HID DPI updates into app state |
| Independent X/Y DPI | `Shipped` | `Shipped` | `supportsIndependentXYDPI` is true on both transports |
| Poll rate | `Shipped` | `Hidden` | USB uses the shared `getPollRate` / `setPollRate` path; BT hard-codes `poll_rate: nil` and `capabilities.poll_rate: false` |
| Sleep timeout | `Shipped` | `Shipped` | USB reads idle time; BT reads `powerTimeoutGet` and exposes the same power-management card |
| Low battery threshold | `Shipped` | `Hidden` | USB reads and writes threshold values; BT does not populate `low_battery_threshold_raw`, so the current app never shows the threshold card there |
| Battery telemetry | `Shipped` | `Shipped` | BT state publishes battery percent; BT charging is only surfaced when a USB fallback session can verify it |
| Lighting: brightness + static color | `Shipped` | `Shipped` | USB ships three onboard zones; BT ships per-zone brightness and per-zone static color on `0x01`, `0x04`, and `0x0A`. The V3 USB family is modeled with 14 individually addressable Custom Frame cells (1 logo + 1 scroll wheel + 12 underglow/tail cells) via `Class 0x0F Cmd 0x03`, which OpenSnek uses for volatile USB Advanced software lighting while the app/service is running; see [docs/research/BASILISK_V3_PRO_PERLED_UNDERGLOW.md](./research/BASILISK_V3_PRO_PERLED_UNDERGLOW.md). OpenSnek's onboard model remains the shipped three-zone subset. |
| Lighting: extra effects | `Shipped` | `Limited` | USB advertises the shared onboard Basilisk V3 USB family set: `off`, `static`, `spectrum`, and `wave`. V3 Pro USB also exposes Advanced software presets, including the Battery Meter underglow progress bar gated to this profile because it is the shipped device with both the light strip and battery telemetry. BT is static-only because the BT profile advertises only `.staticColor` |
| Button remap: shipped editable slots | `Shipped` | `Shipped` | USB writable slots are `1-5`, `9`, `10`, `15`, `52`, `53`, and `96`; BT writable slots are `1-5`, `9`, `10`, `52`, `53` |
| Button remap: unsupported slots | `Hidden` | `Hidden` | USB slot `14` and profile button `106` are kept out of the editable layout; BT clutch `15` and profile button `106` are also kept out of the editable layout and only appear as unsupported footnotes |
| Scroll controls | `Shipped` | `Hidden` | V3 Pro USB uses profile-scoped `get/setScrollMode`, `get/setScrollAcceleration`, and `get/setScrollSmartReel`; BT never publishes those fields and the UI excludes BT scroll controls |
| Onboard hardware profiles | `Shipped` | `Shipped` | V3 Pro USB and BT expose inventory-backed mapped core profile CRUD: list, read, create, rename, update, delete/unassign, activate, and passive profile-cycle refresh. Profile snapshots include metadata, DPI, mapped button bindings, brightness, USB scroll controls, USB/BT static color where mapped, and leave global settings plus advanced profile surfaces outside the v1 profile snapshot. |

## Basilisk V3 35K

USB PID `0x00CB`, no Bluetooth transport

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Validated` | `No transport` | USB profile is locally validated |
| DPI stages + active stage | `Shipped` | `No transport` | Real-time passive HID updates are shipped on the USB path |
| Independent X/Y DPI | `Shipped` | `No transport` | `supportsIndependentXYDPI` is true |
| Poll rate | `Shipped` | `No transport` | Uses the shared USB poll-rate path |
| Sleep timeout | `Shipped` | `No transport` | Uses the shared USB idle-time path |
| Low battery threshold | `Shipped` | `No transport` | Uses the shared USB threshold path |
| Battery telemetry | `Shipped` | `No transport` | Uses the shared USB battery path |
| Lighting: brightness + static color | `Shipped` | `No transport` | The USB profile ships three zones: `scroll_wheel`, `logo`, and `underglow` |
| Lighting: extra effects | `Shipped` | `No transport` | The 35K USB profile advertises the shared Basilisk V3 USB family set: `off`, `static`, `spectrum`, and `wave` |
| Button remap: shipped editable slots | `Shipped` | `No transport` | Writable slots are `1-5`, `9`, `10`, `15`, `52`, `53`, and `96` |
| Button remap: unsupported slots | `Hidden` | `No transport` | Slot `14` and slot `106` are documented as unsupported footnote entries rather than editable controls |
| Scroll controls | `Shipped` | `No transport` | The 35K USB profile uses the shared `get/setScrollMode`, `get/setScrollAcceleration`, and `get/setScrollSmartReel` implementation |
| Onboard hardware profiles | `Shipped` | `No transport` | The 35K USB profile exposes the shared inventory-backed core profile CRUD surface: list, read, create, rename, update, delete/unassign, activate, and passive profile-cycle refresh |

## Basilisk V3 Pro 35K Phantom Green Edition

Bluetooth vendor `0x068E` / PID `0x00D8` (advertised as `BSKV3P 35K`). OpenRazer lists this edition's USB IDs as `0x00D6` (wired) / `0x00D7` (receiver), but OpenSnek does not claim USB yet. Support is based on hardware validation by [PLus123456](https://github.com/PLus123456); evidence lives in [captures/ble/2026-10-13-basilisk-v3-pro-35k](../captures/ble/2026-10-13-basilisk-v3-pro-35k/README.md).

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Not shipped` | `Contributor validated` | Bluetooth was exercised on physical hardware with `OpenSnekProbe` and the app |
| DPI stages + active stage | `Not shipped` | `Contributor validated` | Live table `0B 84 01 00` read/write; passive HID reports follow the DPI button through written stages. Ceiling `35,000` |
| Independent X/Y DPI | `Not shipped` | `Mapped` | Inherits the Basilisk V3 Pro Bluetooth X/Y pair encoding |
| Poll rate | `Not shipped` | `Hidden` | Same as the Basilisk V3 Pro Bluetooth path |
| Sleep timeout | `Not shipped` | `Contributor validated` | `05 84 00 00` read `300 s` |
| Battery telemetry | `Not shipped` | `Contributor validated` | Vendor raw `05 81 00 01` is always read on its 0-255 scale (`0x7B` = 48%); charging is only trusted from a USB fallback session |
| Lighting: brightness + static color | `Not shipped` | `Contributor validated` | Two zones: scroll wheel `0x01` and underglow `0x0A`. The firmware still lists LED `0x04`, but this edition has no logo LED |
| Lighting: extra effects | `Not shipped` | `Limited` | Static color only, like the Basilisk V3 Pro Bluetooth path |
| Button remap: shipped editable slots | `Not shipped` | `Contributor validated` | Basilisk V3 family slots `1-5`, `9`, `10`, `15`, `52`, `53`, `96`; keyboard and turbo writes on slots `4`/`5` were acknowledged. Slot `15` defaults to the compact clutch block `06 01 05 01 90 01 90` read from the factory banks |
| Button remap: unsupported slots | `Not shipped` | `Hidden` | Profile button `106` stays a read-only footnote, as on the Basilisk V3 Pro Bluetooth path |
| Onboard hardware profiles | `Not shipped` | `Single slot` | `03 84` metadata reads return status `0x03` on every target, so mapped profile CRUD is off; edits use the live keys |
| Persistence | `Not shipped` | `Limited` | A power cycle restores the mouse's own lighting and DPI table; use an OpenSnek local profile with restore-on-connect to re-apply settings |

## Orochi V2

Bluetooth PID `0x0095`; 2.4 GHz HyperSpeed dongle path not yet shipped.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Not shipped` | `Contributor validated` | Bluetooth profile is based on contributor-validated DPI stages, battery, and no-RGB capability behavior |
| DPI stages + active stage | `Not shipped` | `Contributor validated` | Contributor validated Bluetooth stage readback with five stages up to `18,000` DPI |
| Independent X/Y DPI | `Not shipped` | `Scalar only` | The profile ships scalar DPI only because `supportsIndependentXYDPI` is false |
| Poll rate | `Not shipped` | `Hidden` | Bluetooth state hard-codes `poll_rate: nil` and `capabilities.poll_rate: false` |
| Sleep timeout | `Not shipped` | `Mapped` | Rides the shared Bluetooth `powerTimeoutGet` / `powerTimeoutSet` path; Orochi-specific read/write validation is still pending |
| Low battery threshold | `Not shipped` | `Hidden` | Bluetooth does not populate `low_battery_threshold_raw`, so the app never renders the threshold card |
| Battery telemetry | `Not shipped` | `Contributor validated` | Contributor validated Bluetooth battery reads; OpenSnek reports `charging = false` for this AAA-powered profile |
| Lighting: brightness + static color | `Not shipped` | `Hidden` | The profile declares no lighting effects, zones, or LED IDs; Bluetooth state reports `capabilities.lighting = false` |
| Lighting: extra effects | `Not shipped` | `Hidden` | Orochi V2 has no RGB lighting |
| Button remap: shipped editable slots | `Not shipped` | `Mapped` | Profile metadata maps slots `1-5`, `9`, `10`, and `96`, but hardware read/write/readback validation is still pending |
| Button remap: unsupported slots | `Not shipped` | `Hidden` | No extra unsupported Orochi-specific slots are documented yet |
| Scroll controls | `Not shipped` | `Hidden` | Bluetooth never publishes scroll-control state fields and the UI excludes BT scroll controls |
| Onboard hardware profiles | `Not shipped` | `Single slot` | Profile ships with `onboardProfileCount = 1` |

## Naga Pro

USB PIDs `0x008F` (wired) / `0x0090` (2.4 GHz receiver), Bluetooth PID `0x0092`.

Support is based on hardware validation reported by [varunyellina in PR #106](https://github.com/gh123man/OpenSnek/pull/106), with side-panel defaults and physical press validation contributed by [jpagh in PR #121](https://github.com/gh123man/OpenSnek/pull/121); OpenSnek maintainers do not currently possess this device. A later contributor session on a `0x0090` receiver added 2-button-panel press validation, an inventory cross-check, and the underside profile button's factory block, which made slot `14` editable; see the [2026-10-17 addendum](../captures/usb/2026-10-06-naga-pro-side-panel-validation/README.md).

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `Contributor validated` | The contributor exercised wired, receiver, and Bluetooth paths on physical hardware |
| DPI stages + active stage | `Contributor validated` | `Contributor validated` | Scalar DPI is capped at `20,000` |
| Independent X/Y DPI | `Scalar only` | `Scalar only` | The Naga Pro profile intentionally does not advertise independent X/Y editing |
| Lighting: brightness + static color | `Contributor validated` | `Contributor validated` | OpenSnek exposes scroll-wheel `0x01` and logo `0x04` zones; advanced effects are not claimed |
| Button remap: shipped editable slots | `Limited` | `Limited` | Body/2-button-panel slots `1-5`, `9`, `10`, `11`, `12`, `14`, `52`, `53`; 12-button panel slots `64-75`; and 6-button panel slots `80-85` are editable with captured native `Default` blocks. Slots `11`/`12` are the DPI buttons and slot `14` the underside profile button. The 2-button panel is press-validated: forward = slot `5` (mouse button 5), rear = slot `4` (mouse button 4) |
| Button remap: preserved slots | None | None | Every mappable slot is editable. The underside profile button (slot `14`) cycles the saved onboard profiles; its unassigned banks hold the factory `07 01 04` block, which `Default` restores, and the slot round-trips remaps |
| Onboard hardware profiles | `Limited` | `Limited` | Five-slot mapped core profile workflows ship, and full button-profile reset now uses captured native side-panel defaults. The 12- and 6-button panels were physically press-validated in [PR #121](https://github.com/gh123man/OpenSnek/pull/121), and the 2-button panel on 2026-10-17 |
| Button inventory cross-check | `Contributor validated` | `No transport` | `02:84` reports 30 mappable slots, exactly matching the shipped `nagaProUSBButtonSlots` table, so the profile has no missing slots |

The remaining device-dependent work is tracked in [issue #56](https://github.com/gh123man/OpenSnek/issues/56).

## Naga V2 Pro

USB PIDs `0x00A7` (wired) / `0x00A8` (2.4 GHz receiver), Bluetooth vendor `0x068E` / PID `0x00A9`. Support is based on hardware validation by [jpagh](https://github.com/jpagh) with all three side panels and the bottom button.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `Contributor validated` | Wired, receiver, and Bluetooth were exercised on physical hardware |
| DPI stages + active stage | `Contributor validated` | `Contributor validated` | Scalar DPI is capped at `30,000`; the live table and scalar write/readback were validated |
| Independent X/Y DPI | `Scalar only` | `Scalar only` | The profile does not advertise independent X/Y editing |
| Poll rate | `Contributor validated` | `Not exposed` | `1,000 Hz` read; a `500 Hz` write/readback with restore was validated over USB. No Bluetooth vendor key is mapped yet |
| Battery + power | `Contributor validated` | `Contributor validated` | USB reads `07:80`; Bluetooth uses vendor keys `05 81 00 01` / `05 80 00 01`. Both report `0x45` = 27%, matching Synapse; the standard HID battery characteristic reports a stale 100% |
| Lighting: brightness + effects | `Contributor validated` | `Contributor validated` | Two zones: palm logo `0x04` and the 12-button side panel `0x05`, with whole-device brightness on LED `0x00`. The 6- and 2-button plates have no lighting. Bluetooth exposes static color only |
| Lighting: software presets | `Contributor validated` | `Not exposed` | Custom frames (`0F:03`) render the animated OpenSnek presets to the logo over USB |
| Button remap: shipped editable slots | `Contributor validated` | `Contributor validated` | Body slots `1-5`, `9`, `10`, `14`, `52`, `53` and side-panel slots `64-75` (12-button) and `80-85` (6-button) are editable; writes round-trip on the receiver, wired, and Bluetooth |
| Button remap: preserved slots | `Contributor validated` | `Contributor validated` | Top buttons `0x60` (DPI stage down) and `0x6D` (DPI stage up) answer reads and accept writes but stay read-only until a dedicated DPI-stage binding kind ships |
| Onboard hardware profiles | `Limited` | `Not exposed` | Five-slot mapped core profile workflows ship over USB; the full-reset path covers every writable slot. Bluetooth profile CRUD stays hidden because create/delete writes are not validated yet |
| Scroll controls (wheel mode / acceleration / smart reel) | `Not shipped` | `Not shipped` | `supportsScrollModeControls` is false, so OpenSnek never reads or writes wheel mode, scroll acceleration, or smart reel on this device and hides those controls. The device rejects the scroll-mode pair (`02:94` returns `0x05`), and the mouse has no free-spin wheel, so there is nothing for the app to adjust |
| Side-panel physical labels | `Contributor validated` | `Contributor validated` | Press validation confirmed 12-button labels `1-12` → slots `64-75` and 6-button labels `1-6` → slots `80-85` on the receiver and Bluetooth |
## Naga V3 Pro

USB PIDs `0x00E7` (wired) and `0x00E8` (2.4 GHz receiver); Bluetooth `068E:00E9`.
Support is based on hardware validation by
[jpagh](https://github.com/jpagh); the profile carries `isLocallyValidated: false` because it has not
been validated on maintainer hardware. The wired follow-up confirmed the same transaction ID,
button inventory/defaults, and three lighting zones, with reversible poll-rate, X/Y DPI,
sleep-timeout, and per-zone brightness writes; see
[the wired capture](../captures/usb/2026-10-18-naga-v3-pro-wired/README.md).
The [Bluetooth capture](../captures/ble/2026-10-18-naga-v3-pro/README.md) records
stage/power/lighting read-write-restore, button remap/Default, eight visually checked effects,
and off/on plus finite idle/wake recovery. The [gap follow-up](../captures/ble/2026-10-18-naga-v3-pro/follow-up/README.md)
adds all 33 slots on both BLE targets, direct six-button label validation, and one isolated power-cycle
check: DPI/sleep timeout/brightness persisted; live static color reverted. Bluetooth poll rate and profile CRUD remain hidden.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `Contributor validated` | USB uses transaction ID `0x1F`; BLE `00E9` uses the vendor GATT service and eight-byte notify headers |
| DPI stages + active stage | `Contributor validated` | `Contributor validated` | Five stages, preserving stage IDs and active token. The latest wired/BLE baseline includes a 50,000-DPI fifth stage; BLE hardware multi/single-stage stability sequence passed with baseline restored |
| Independent X/Y DPI | `Contributor validated` | `Contributor validated` | USB `800x1600` and BLE `1700x1800` changed writes read back and restore; both profile paths enable independent X/Y |
| DPI ceiling | `Contributor validated` | `Contributor validated` | Published Focus Pro 50K ceiling `50,000`; BLE merge/write paths use the profile ceiling rather than a hard-coded 30,000 clamp |
| Poll rate | `Contributor validated` | `Not shipped` | USB 1000 → 500 → 1000 Hz read/write/restore. No Bluetooth poll-rate command is claimed |
| Battery + power | `Contributor validated` | `Contributor validated` | USB level/charging and sleep-timeout writes; BLE byte-scaled vendor battery and sleep timeout. BLE charging status is unreliable and stays unknown without USB fallback |
| Lighting: brightness + effects | `Contributor validated` | `Contributor validated` | Scroll wheel `01`, logo `04`, side panel `05`; per-zone brightness and static writes restored. All eight effects visually checked over BLE. The 6-/2-button plates have no lighting |
| Button remap: shipped editable slots | `Contributor validated` | `Contributor validated` | Shared 33-slot layout. USB every slot same-value write/readback; BLE all 33 shipped slots changed-write/readback/restore on both live and persistent targets, with all 66 originals verified afterward; UI rear-scroll key/Default physically checked |
| Button remap: physical labels | `Contributor validated` | `Contributor validated` | Shared physical front/rear labels and IDs: index `11/12`, scroll `106/128`, underside profile `14`, pinky `57`; six-button printed labels `1...6` directly press-validated over BLE as slots `80...85` |
| Button inventory cross-check | `Contributor validated` | `Inherited layout` | USB `02:84` reports 33 slots. No independent BLE inventory sweep is claimed |
| Scroll wheel mode button | `Contributor validated` | `Profile mapped` | Front scroll button `106` factory block `12 01 01` cycles wheel mode; rear `128` factory block `00 01 00` does nothing. Both defaults read over BLE; rear changed remap/Default physically checked over BLE; front cycle restore physically checked over USB |
| Scroll controls (wheel mode / acceleration / smart reel) | `Not shipped` | `Not shipped` | No identified setting readout/control; USB scroll-mode query rejects with status `05`. Use the front button's factory action or Synapse |
| Onboard hardware profiles | `Hidden` | `Hidden` | USB metadata reads reject; BLE profile CRUD not validated. Stored-bank USB findings are not claims about BLE profile support |

Plate note: the owner has all three plates. Press validation on the 2-button plate confirmed the same
reversed mapping the Naga Pro family uses — the forward button is slot `5` and the rear button is slot
`4` — and the same test on a Naga Pro (`0x0090`) receiver produced the identical result, so the family
agrees. The plate has no printed labels, so the app uses "Panel Button (front/rear)" names following physical
position. The 6-button plate's printed labels `1...6` were directly press-validated on this V3 Pro
(output `123456` in label order), confirming slots `80...85` and the same physical wrapping as the
Naga V2 Pro. **Neither the 6- nor the 2-button
plate has any lighting**, so LED `0x05` only lights the 12-button plate. The firmware does not report
which plate is fitted.

Bring-up note: prefer `OpenSnekProbe usb-button-inventory` over a hand-built slot table when adding a
new device. The inventory is what caught slot `128` here.

## Basilisk (2017)

Support for this device and the Lancehead Tournament Edition below is based on hardware validation reported by [johnhenry in PR #114](https://github.com/gh123man/OpenSnek/pull/114).

USB PID `0x0064`, no Bluetooth transport. This is the original 2017 Basilisk; it is not part of the Basilisk V3 USB family assumptions. Ships transaction ID `0x1F` (contributor validated; hardware also answers OpenRazer's `0x3F`).

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | OpenRazer-derived profile with contributor hardware validation of DPI, poll-rate reads, and lighting (write + readback + restore) |
| DPI stages + active stage | `Contributor validated` | `No transport` | Clamped to `16,000`. Contributor hardware returned a live 5-stage table (`04:86`) with active-stage tracking even though OpenRazer never exposed stages for this device |
| Independent X/Y DPI | `Contributor validated` | `No transport` | Distinct X/Y writes read back exactly on contributor hardware |
| Poll rate | `Contributor validated` | `No transport` | Poll-rate reads validated (500 Hz observed); writes ride the shared USB path |
| Sleep timeout | `Not shipped` | `No transport` | Wired mouse; `supportsPowerManagementControls` is false |
| Low battery threshold | `Not shipped` | `No transport` | Wired mouse; no battery |
| Battery telemetry | `Not shipped` | `No transport` | Wired mouse; no battery |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | Two zones: scroll wheel `0x01` and logo `0x04`; brightness and static color validated with write + readback + restore |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, `reactive`, and the pulse set validated on contributor hardware; OpenRazer does not expose wave on this device |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | `supportsButtonRemapControls` is false; no capture-backed function-block layout exists yet |
| Button remap: unsupported slots | `Hidden` | `No transport` | The standard mouse slots are visible read-only in the profile metadata |
| Scroll controls | `Not shipped` | `No transport` | `supportsScrollModeControls` is false |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1` |

## Lancehead Tournament Edition

USB PID `0x0060` (wired), no Bluetooth transport. Ships transaction ID `0x1F` (contributor validated; hardware also answers OpenRazer's `0x3F`).

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | OpenRazer-derived profile with contributor hardware validation of DPI, poll-rate reads, and all four lighting zones (write + readback + restore) |
| DPI stages + active stage | `Contributor validated` | `No transport` | Clamped to `16,000`. Contributor hardware returned a live 5-stage table under transaction `0x1F`; OpenRazer's `0xFF` stage-transaction quirk was not needed |
| Independent X/Y DPI | `Contributor validated` | `No transport` | Distinct X/Y writes read back exactly on contributor hardware |
| Poll rate | `Contributor validated` | `No transport` | Poll-rate reads validated (500 Hz observed); writes ride the shared USB path |
| Sleep timeout | `Not shipped` | `No transport` | Wired mouse; `supportsPowerManagementControls` is false |
| Low battery threshold | `Not shipped` | `No transport` | Wired mouse; no battery |
| Battery telemetry | `Not shipped` | `No transport` | Wired mouse; no battery |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | Four zones: scroll wheel `0x01`, logo `0x04`, left side `0x11`, right side `0x10`; per-zone brightness and static color validated with write + readback + restore |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, `wave`, `reactive`, and the pulse set validated on contributor hardware |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | `supportsButtonRemapControls` is false; no capture-backed function-block layout exists yet |
| Button remap: unsupported slots | `Hidden` | `No transport` | The standard mouse slots are visible read-only in the profile metadata |
| Scroll controls | `Not shipped` | `No transport` | `supportsScrollModeControls` is false |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1`; OpenRazer exposes VARSTORE DPI stages but OpenSnek has not mapped a profile CRUD surface for this device |

### Saved-settings reconnect validation

Automatic restore omits sleep timeout and battery-threshold writes for both wired profiles, including snapshots saved with mouse-editor defaults. Unit coverage checks initial restore, disconnect without further writes, and reconnect restoring DPI, poll rate, and lighting while preserving the live active DPI stage.

Maintainer hardware validation remains pending: select a saved local profile with restore-on-connect enabled, change the mouse's active DPI stage, unplug it, and reconnect. Confirm lighting and the saved DPI table return, the live active stage remains selected, and the event log contains no power-setting writes or restore failures.

## Huntsman Mini

Support for this keyboard and the Tartarus Pro below is based on hardware validation reported by [johnhenry in PR #115](https://github.com/gh123man/OpenSnek/pull/115).

USB PID `0x0257`, no Bluetooth transport. Keyboard (`formFactor = .keyboard`); the first non-mouse device profile in OpenSnek. Ships transaction ID `0x1F` (contributor validated; OpenRazer uses `0x3F`). The JP variant (`0x0269`) and the Analog variant (`0x0282`) are not registered.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | Lighting-only profile; contributor hardware validated serial/effects/brightness over the 90-byte feature-report interface |
| DPI stages + active stage | `Not shipped` | `No transport` | The keyboard has no DPI hardware; `supportsDPIControls` is false and USB state reads skip DPI commands, using serial/firmware reads for reachability |
| Independent X/Y DPI | `Not shipped` | `No transport` | No DPI hardware |
| Poll rate | `Not shipped` | `No transport` | Contributor hardware returns `status 0x05` (unsupported) for poll-rate reads, confirming `supportsPollRateControls = false` |
| Sleep timeout | `Not shipped` | `No transport` | Wired keyboard; no power management |
| Low battery threshold | `Not shipped` | `No transport` | Wired keyboard; no battery |
| Battery telemetry | `Not shipped` | `No transport` | Wired keyboard; no battery |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | One zone: backlight LED `0x05`; brightness and static color validated with write + readback + restore |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, `wave`, `reactive`, and the pulse set validated on contributor hardware; OpenRazer's starlight and per-key custom-frame effects (5x15 matrix) are not shipped |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | Key remap is not mapped; the profile ships an empty button layout |
| Button remap: unsupported slots | `Hidden` | `No transport` | No slots are documented |
| Scroll controls | `Not shipped` | `No transport` | Not applicable to a keyboard |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1`; USB state reads skip the mouse onboard-profile commands for non-mouse form factors |

## Tartarus Pro

USB PID `0x0244`, no Bluetooth transport. Keypad (`formFactor = .keypad`). Uses USB transaction ID `0x1F`; contributor hardware validated breathing/pulse effects under `0x1F` too, so OpenRazer's `0x3F` breath quirk needs no per-effect override.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | Lighting-only profile; contributor hardware validated serial/effects/brightness over the 90-byte feature-report interface |
| DPI stages + active stage | `Not shipped` | `No transport` | No DPI hardware; `supportsDPIControls` is false and USB state reads skip DPI commands, using serial/firmware reads for reachability |
| Independent X/Y DPI | `Not shipped` | `No transport` | No DPI hardware |
| Poll rate | `Not shipped` | `No transport` | Contributor hardware returns `status 0x05` (unsupported) for poll-rate reads; OpenRazer does not register poll-rate controls either |
| Sleep timeout | `Not shipped` | `No transport` | Wired keypad; no power management |
| Low battery threshold | `Not shipped` | `No transport` | Wired keypad; no battery |
| Battery telemetry | `Not shipped` | `No transport` | Wired keypad; no battery |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | Effects target backlight LED `0x05`; brightness keeps OpenRazer's LED `0x00` addressing via `usbBrightnessLEDIDs`. Contributor hardware showed LED `0x00` and `0x05` alias the same brightness register (writes to either update both readbacks) |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, `wave`, `reactive`, and the pulse set validated on contributor hardware; starlight and per-key custom frames are not shipped |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | Key remap and analog actuation have no public protocol (OpenRazer exposes neither); the profile ships an empty button layout |
| Button remap: unsupported slots | `Hidden` | `No transport` | No slots are documented |
| Scroll controls | `Not shipped` | `No transport` | Not applicable to a keypad |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1`. OpenRazer deliberately never switches the Tartarus Pro into driver mode (`DRIVER_MODE = False`) because its analog input handling misbehaves; OpenSnek likewise only reads device mode and must not write mode `0x03` to this device |

### Lighting-only connection and restore validation

Initial reads and reconnect recovery require lighting brightness but do not require unsupported DPI or poll-rate telemetry. Saved-settings restore and USB backend applies filter DPI, poll-rate, power-management, and remapping fields according to the device profile, preserving lighting even when a saved snapshot contains mouse-editor defaults.

Unit coverage checks initial connection, no restore writes while disconnected, lighting restore after reconnect, and continued rejection of missing brightness telemetry. Maintainer hardware validation remains pending: select a saved lighting profile with restore-on-connect enabled, unplug and reconnect each device, and confirm the backlight returns without a disconnected status or unsupported mouse-command failures. On the Tartarus Pro, also verify ordinary analog/key input remains functional.

## Razer Mouse Dock

USB PID `0x007E`, no Bluetooth transport. Lighting-only accessory (`formFactor = .accessory`) with a single logo LED (`0x00`) driven by the extended-matrix effect family (`0x0F:0x02`) and brightness (`0x0F:0x04`). Ships transaction ID `0x1F` (contributor validated; OpenRazer sets `0x3F` for this device).

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | Lighting-only profile; contributor hardware validated static color and brightness with visual confirmation, and spectrum/off/pulse writes ACK with `status 0x02` over the 90-byte feature-report interface. OpenSnek keeps the dock connected despite its unreadable effect/brightness state |
| DPI stages + active stage | `Not shipped` | `No transport` | No DPI hardware; `supportsDPIControls` is false |
| Independent X/Y DPI | `Not shipped` | `No transport` | No DPI hardware |
| Poll rate | `Not shipped` | `No transport` | Not a mouse; `supportsPollRateControls` is false |
| Sleep timeout | `Not shipped` | `No transport` | Charging accessory; no power management |
| Low battery threshold | `Not shipped` | `No transport` | The dock reports no battery; `usb-battery-read` returns unavailable |
| Battery telemetry | `Not shipped` | `No transport` | The docked mouse keeps reporting its own battery through its own transport |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | One zone: logo LED `0x00`; brightness and static color validated with write and visual confirmation |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, and the pulse set ACK on contributor hardware; OpenRazer lists no wave or reactive effects for this dock, so they are not exposed |
| Lighting: Battery Meter preset | `Contributor validated` | `No transport` | Software lighting preset that mirrors a connected mouse's battery: configurable low/medium thresholds, low/medium/high palette colors, and a selectable battery source device (defaults to the first connected device that reports battery telemetry; an explicitly selected source is always honored and reads as unavailable while that device is not connected or not responding). The low color flashes below its threshold |
| Lighting: software presets | `Contributor validated` | `No transport` | The animated OpenSnek software presets (flame, scrolling rainbow, comet chase, night rider, aurora, jellybeans) render to the single logo cell via custom frames |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | The dock has no buttons; the profile ships an empty button layout |
| Button remap: unsupported slots | `Hidden` | `No transport` | No slots are documented |
| Scroll controls | `Not shipped` | `No transport` | Not applicable to a dock |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1` |

Readback note: the dock does not answer the effect-state (`0x0F:0x82`) or brightness (`0x0F:0x84`) reads, so OpenSnek reports effect state and brightness as unavailable after reconnect. Writes are still accepted and take effect immediately.

## Razer Mouse Dock Pro

USB PID `0x00A4`, no Bluetooth transport. Lighting-only accessory (`formFactor = .accessory`) with
a single logo LED (`0x00`) driven by the extended-matrix effect family (`0x0F:0x02`) and brightness
(`0x0F:0x04`). Support is based on hardware validation by [jpagh](https://github.com/jpagh) and has
not been validated on maintainer hardware.

This dock is **not** interchangeable with the original Mouse Dock: it answers only transaction ID
`0xFF` (OpenRazer sets the same value), and every request sent with `0x1F` or `0x3F` returns status
`0x04`. The shipped profile pins `usbTransactionID: 0xFF`.

| Feature Area | USB | BT | Notes |
|---|---|---|---|
| Overall transport status | `Contributor validated` | `No transport` | Lighting-only profile; contributor hardware validated with visual confirmation of static color, wave, and breathing, and ACK-verified spectrum and pulse effects |
| DPI stages + active stage | `Not shipped` | `No transport` | No DPI hardware; `supportsDPIControls` is false |
| Independent X/Y DPI | `Not shipped` | `No transport` | No DPI hardware |
| Poll rate | `Not shipped` | `No transport` | Not a mouse; `supportsPollRateControls` is false |
| Sleep timeout | `Not shipped` | `No transport` | Charging accessory; no power management |
| Low battery threshold | `Not shipped` | `No transport` | The dock reports no battery |
| Battery telemetry | `Not shipped` | `No transport` | A docked mouse keeps reporting its own battery through its own transport |
| Lighting: brightness + static color | `Contributor validated` | `No transport` | One zone: logo LED `0x00`. Brightness writes and reads were both validated with restore; reads use LED `0x0F` while writes use `0x00`, so the profile splits the write and read addresses |
| Lighting: extra effects | `Contributor validated` | `No transport` | `off`, `static`, `spectrum`, `wave`, and the pulse set ship. Wave is supported here (unlike the original Mouse Dock) with both directions, and breathing was visually confirmed. `reactive` is not in OpenRazer's method list for this device and is not exposed |
| Lighting: software presets | `Not shipped` | `No transport` | OpenRazer declares a `1x8` matrix and the dock ACKs 1-, 4-, and 8-cell row writes, but per-cell rendering is not mapped yet, so no frame layout ships. As a result this dock has **no Battery Meter preset and no animated software presets**, unlike the original Mouse Dock, which is a visible difference the owner called out |
| Button remap: shipped editable slots | `Not shipped` | `No transport` | The dock has no buttons; the profile ships an empty button layout |
| Scroll controls | `Not shipped` | `No transport` | Not applicable to a dock |
| Onboard hardware profiles | `Single slot` | `No transport` | Profile ships with `onboardProfileCount = 1` |

Service note: if the dock opens cleanly but every write fails with `kIOReturnTimeout`
(`0xE00002D6`) across all report IDs and both feature and output report types, treat it as a stale
HID session and replug the dock before changing protocol logic. Removing Razer Synapse alone did not
clear that state during this pass; the replug did.

Addressing note: `0F:84` reads at LED `0x00` always answer `00`, which looks like a dark dock even at
full brightness. The stored value is readable at LED `0x0F`, and `0F:82` echoes LED `0x0F` no matter
which LED was requested, so associate effect responses with the requested LED rather than that echo.

## References

- [Protocol Index](./protocol/PROTOCOL.md)
- [USB/BLE Parity](./protocol/PARITY.md)
- [Build, Probe, and Validation Notes](../OpenSnek/README.md)
