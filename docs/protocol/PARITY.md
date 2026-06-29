# USB/BLE Feature Parity

This document is the single source of truth for feature parity between the USB HID protocol and BLE protocol paths in `open-snek`.

## Scope

Target device baseline:
- Basilisk V3 X HyperSpeed (`USB PID 0x00B9`, `BT PID 0x00BA`)
- Basilisk V3 (`USB PID 0x0099`, OpenRazer-backed USB profile only)
- Basilisk V3 Pro (`USB PIDs 0x00AA, 0x00AB`)
- Basilisk V3 Pro Bluetooth (`BT PID 0x00AC`)
- Basilisk V3 35K (`USB PID 0x00CB`)
- Orochi V2 Bluetooth (`BT PID 0x0095`)

Transport paths:
- USB/2.4GHz: 90-byte HID report protocol
- BLE: vendor GATT (`...1524`/`...1525`) + selective HID fallback

## Parity Matrix

Legend:
- `DONE`: implemented and documented on both paths
- `PARTIAL`: implemented but transport-dependent or not fully mapped
- `USB_ONLY`: available only on USB path
- `BLE_ONLY`: available only on BLE path
- `UNKNOWN`: protocol not fully decoded

| Feature | USB Protocol | BLE Protocol | Script Support | Status | Notes |
|---|---|---|---|---|---|
| Serial read | `00:82` | key `01 83 00 00` | `razer_usb.py` + `razer_ble.py` (USB HID + BT vendor fallback) | DONE | BT vendor fallback implemented |
| Firmware read | `00:81` | unknown vendor key | `razer_usb.py` + `razer_ble.py` (HID path) | PARTIAL | HID over BT may fail on some stacks |
| Device mode | `00:84/04` | `01 82 00 00` (read), `01 02 00 00` (write candidate) | `razer_usb.py` + `razer_ble.py` | PARTIAL | BT read fallback enabled; BT write path disabled for safety. OpenSnek writes/reads mode on USB and shows the card only when readback is available. |
| DPI XY | `04:85/05` | passive HID read/listen; live apply via vendor stage writes | both scripts | PARTIAL | direct BT HID `set_dpi` is not reliable on validated stack, but OpenSnek now uses validated passive BT HID reports for immediate on-device DPI-change updates |
| DPI stages + active stage | `04:86/06` | `0B84`/`0B04`, `op=0x26` | both scripts | DONE | OpenSnek normalizes active-stage via stage IDs and preserves USB stage IDs on writes to avoid off-by-one stage mapping. |
| Poll rate | `00:85/05` | HID fallback only | both scripts | PARTIAL | Need BLE vendor equivalent |
| Battery level | `07:80` | Battery Service + observed vendor read | both scripts | PARTIAL | Charging-state parity still incomplete on BLE |
| Idle time | `07:83/03` | `05 84 00 00` / `05 04 00 00` | both scripts | DONE | BT vendor fallback implemented |
| Low battery threshold | `07:81/01` | `05 82 00 00` / `05 02 00 00` | both scripts | DONE | BT vendor fallback implemented. OpenSnek supports read/write on USB + BT, and hides USB control when unsupported. |
| Scroll mode | `02:94/14` | unknown vendor key | both scripts (HID path) | PARTIAL | USB profile-scoped semantics use the first command argument as storage/profile ID. OpenSnek reads/writes on USB and hides the control when unsupported. |
| Scroll acceleration | `02:96/16` | unknown vendor key | both scripts (HID path) | PARTIAL | USB profile-scoped semantics use the first command argument as storage/profile ID. BLE vendor mapping missing. OpenSnek hides the control when unsupported. |
| Scroll smart reel | `02:97/17` | unknown vendor key | both scripts (HID path) | PARTIAL | USB profile-scoped semantics use the first command argument as storage/profile ID. BLE vendor mapping missing. OpenSnek hides the control when unsupported. |
| Scroll LED brightness | `0F:84/04` (`VARSTORE`, `LED=0x01`) | unknown vendor key | both scripts (HID path) | PARTIAL | USB validated; BLE vendor key not mapped |
| Scroll LED effects | `0F:02` (none/spectrum/wave/static/reactive/breath) | unknown vendor key | both scripts (HID path) | PARTIAL | USB validated on Basilisk V3 X; multi-zone IDs are also validated on Basilisk V3 Pro / 35K |
| Button remapping | class `0x02`, `0x8C/0x0C` button-function block | vendor `08 04 01 <slot>` + 10-byte payload | BLE implemented + USB validated (`OpenSnek` + `OpenSnekProbe`) | PARTIAL | USB uses `profile,slot,hypershift` + 7-byte function block (`class,len,data[5]`); BLE wraps the same 7-byte function block after its `profile,slot,layer` prefix. Mouse + single-key keyboard remaps validate on `0x00B9`, including default restore behavior and readback. Modifier shortcuts are implemented from Basilisk capture-backed docs and the shared function-block layout, and still need maintainer hardware readback on Bluetooth. BLE slot `0x06` remains rejected (`status 0x03`); macro/media catalogs are still pending. |
| Lighting/effects | class `0x0F` (OpenRazer documented), including V3-family USB Custom Frame `0F:03` for volatile 14-cell software effects | scalar brightness (`10 85`/`10 05`), legacy frame stream (`10 84`/`10 04`), and V3 Pro zone static state (`10 83`/`10 03`) | USB zone writes + V3-family USB software presets + BLE zone brightness/static-color writes | PARTIAL | OpenSnek ships USB software-driven Custom Frame presets while the app/service is running for V3 USB devices with the shared scroll/logo/underglow lighting model. The Custom Frame path is hardware-validated as 14 cells on V3 Pro USB and assumed for wired V3 / V3 35K until separately validated. OpenSnek also ships static-color Bluetooth lighting for the Basilisk V3 Pro by fanning out per-zone `10 03`/`10 05` writes across `0x01`, `0x04`, and `0x0A`. Advanced BLE effect streaming remains unshipped. |
| Profiles | inventory `05:81` / count `05:80`, active profile `05:84`, active selector `05:04`, profile-addressed setting banks for DPI/buttons/brightness/static color/scroll controls, metadata chunks via `05:88/08`, create/assign prelude `05:02`, delete/unassign via `05:03`, passive profile-cycle HID hint | active target `03 82`, active selector `03 02`, inventory `03 80`, metadata `03 84/04`, create/assign through `03 06` + `08 05`/`08 07` + `03 05` + metadata/content writes, delete/unassign `03 06`, profile-addressed DPI/buttons/lighting, passive profile-cycle HID hint | OpenSnek app + `OpenSnekProbe` profile paths on both transports | DONE | USB and BLE have shipped CRUD parity for shared mapped profile surfaces on validated Basilisk V3 Pro devices: active-profile reads/selectors, inventory/list, stored profile banks, UUID/name reads/writes on assigned profiles, explicit-target create/assign, cycle-ring delete/unassign, static-color snapshots/writes, and physical profile-button hints. USB additionally includes profile-scoped scroll mode, acceleration, and smart reel; Bluetooth has no shipped scroll-control mapping. Both transports reject direct metadata writes to unassigned banks until the create/assign prelude runs. Non-static effect payload editing and advanced profile surfaces remain outside the scoped CRUD API. |

## Current Priorities

1. Decode remaining BLE vendor keys for USB-equivalent controls:
- poll rate
- scroll mode / acceleration / smart reel
- firmware

2. Expand advanced button/profile action taxonomy:
- validate advanced classes (consumer/media, macro families, analog variants)
- document and implement advanced profile surfaces only after they have product-level software support

3. Build common feature abstraction:
- one logical setting model with transport-specific encoders
- predictable fallback ordering per feature

## Validated Device Profile (Basilisk V3 X HyperSpeed, USB PID `0x00B9`)

Validated in-session over USB:
- working: serial, firmware, device mode read/write, poll-rate read/write, idle-time read/write, low-battery-threshold read/write, DPI/stages, battery
- working: OpenSnek now arms the shared passive HID DPI listener on the observed `0x01:0x06` USB interfaces and upgrades to real-time HID updates once the host delivers a live callback
- working: scroll LED brightness + effects (none/spectrum/wave/static/reactive/breath single/dual/random)
- working: button remap read/write on class `0x02` (`0x8C`/`0x0C`) for tested slots (`0x01..0x05`, `0x09`, `0x0A`, `0x60`) with readback confirmation via `OpenSnekProbe` and hardware XCTest harness
- observed non-remappable control on `0x00B9`: Hypershift / Boss-sniper slot `0x06` returns status `0x03` on `0x02:0x8C` reads and is outside the validated USB button-function path
- unsupported (returns `None`): scroll mode, scroll acceleration, scroll smart reel
- legacy non-analog remap write (`0x02:0x0D`) remains unreliable on this model and is now treated as fallback-only

CLI behavior has been updated to skip unsupported scroll controls with warnings instead of failing runs.

## Validated Device Profile (Basilisk V3 35K, USB PID `0x00CB`)

Validated in-session over USB:
- working: serial, firmware, device mode read/write, poll-rate read/write, DPI/stages, battery, core USB telemetry
- working: OpenSnek now arms the shared passive HID DPI listener on the observed `0x01:0x06` USB interfaces and upgrades to real-time HID updates once the host delivers a live callback
- working: matrix brightness/effect writes on all validated LED IDs (`0x01` scroll wheel, `0x04` logo, `0x0A` underglow)
- working: button remap read/write/readback on standard slots plus the additional sensitivity clutch / DPI clutch (`0x0F`), wheel-tilt (`0x34`, `0x35`), and top DPI-button (`0x60`) slots
- observed clutch behavior on `0x00CB`: native slot `0x0F` default reads back as `06 01 05 01 90 01 90`, accepts remap writes, and also accepts the V3 Pro-style `06 05 05 <dpi> <dpi>` DPI-clutch payload; the same DPI-clutch payload also round-trips on slot `0x04`
- observed non-remappable controls on `0x00CB`: scroll-mode (`0x0E`, protocol-read-only), profile button (`0x6A`, protocol-read-only with report-4 `0x50`)
- observed alternate USB DPI-button payload on slot `0x60`: `04 02 0F 7B 00 00 00`
- shipped client behavior: normalize `0x60` to a user-facing `DPI Cycle` action and allow binding `DPI Cycle` to any writable USB slot
- observed HID candidates on an attached `0x00CB`: `0x01:0x06` interfaces with `input=16/8` and `feature=1/0`, matching the tuple already used for the shipped V3 Pro USB passive DPI listener
- client note: `0x02:0x8C` response layout is not identical to `0x00B9`; clients must validate echoed `profile`/`slot` bytes before choosing the 35K function-block offset
- observed profile summary getter on `0x00CB`: `0x00:0x87` -> `<active,0x00,count>`
- tested active-profile write candidates on `0x00CB`: `0x00:0x07` with payloads `02`, `02 00`, `02 00 05`, and `02 00 00` all returned status `0x05` (`not supported`)
- observed profile-model behavior on `0x00CB`: persistent slot `0x05` writes stay isolated, persistent slot `0x01` writes mirror into direct/live `0x00` while profile `1` is active, and later direct/live writes do not write back into persistent slot `0x01`
- shipped client behavior: the 35K USB profile now inherits the shared Basilisk V3 USB mapped core profile configuration, so OpenSnek exposes inventory-backed onboard profile CRUD and direct active-profile reads through the same `0x05` profile commands used by the V3 Pro USB path

## OpenRazer-Backed Device Profile (Basilisk V3, USB PID `0x0099`)

Mapped from current OpenRazer source, not yet validated in-session with OpenSnek hardware:
- OpenRazer advertises the wired Basilisk V3 as `USB PID 0x0099` with `DPI_MAX = 26000`
- OpenSnek maps the wired V3 onto the shared Basilisk V3 USB configuration profile for button slots, multi-zone lighting targets, passive HID DPI/profile-switch listener matching, independent X/Y DPI editing, scroll controls, and mapped core onboard profile CRUD
- OpenSnek caps DPI edits/readback for this profile at `26,000` instead of the 35K profile's `35,000`
- until local protocol captures confirm otherwise, this profile should be treated as best-known support derived from ecosystem sources rather than hardware-validated parity

## Validated Device Profile (Basilisk V3 Pro, USB PIDs `0x00AA` / `0x00AB`)

Validated in-session over USB:
- current alias note: a directly cabled V3 Pro now enumerates as `1532:00AA` on the observed macOS host, and OpenSnek maps it onto the same shipped USB profile as `1532:00AB`
- working: serial, firmware, device mode read/write, poll-rate read/write, DPI/stages, battery, core USB telemetry
- working: matrix brightness/effect writes on all validated LED IDs (`0x01` scroll wheel, `0x04` logo, `0x0A` underglow)
- working: button remap read/write/readback on the shared writable Basilisk slots, wheel-tilt (`0x34`, `0x35`), and the sensitivity clutch / DPI clutch (`0x0F`)
- observed V3 Pro clutch default block on `0x0F`: `06 05 05 01 90 01 90`
- observed V3 Pro clutch DPI parameterization: writing `06 05 05 03 20 03 20` read back cleanly as an 800-DPI clutch payload on slot `0x04`
- observed V3 Pro clutch remap portability: the same block was written/read back successfully on slot `0x04`, so OpenSnek treats `DPI Clutch` as a V3 Pro USB remap action and not only as the native clutch button's default
- observed V3 Pro wheel-tilt scroll blocks on 2026-04-03 after a working Synapse rebind: slot `0x34` read back `0e036800140000` and slot `0x35` read back `0e036900140000` on both persistent and direct layers
- inferred client behavior: OpenSnek now uses that same wheel-tilt block for the shared Basilisk V3 / V3 Pro / 35K USB family because those profiles already share the same tilt slots and action taxonomy; only the V3 Pro form is directly hardware-validated so far
- shipped client behavior: OpenSnek exposes slot `0x60` as the V3 Pro top DPI button so non-HyperSpeed Basilisk V3 profiles share the same editable button map; V3 Pro USB default restore uses the standard DPI-cycle block `06 01 06 00 00 00 00`
- observed profile-button default block on `0x6A`: `12 01 01 00 00 00 00`
- observed profile-button remap behavior on `0x6A`: right-click writes/readback can succeed, but repeated write/readback cycles later returned timeout/no-response frames; OpenSnek keeps this slot hidden until the USB ACK/readback path is reliable
- observed non-match on `0x60`: it does not read back like the 35K top DPI-button block, so OpenSnek does not use the 35K-specific native restore payload for V3 Pro
- client note: `0x02:0x8C` response layout on the observed extended slots matches the 35K-style offset (`response[11..<18]`) rather than the Basilisk V3 X shape
- observed V3 Pro profile summary reads from `0x00:0x87` have not been trustworthy enough to ship as UI state: on March 25, 2026 the bottom profile LED changed while the register continued to report `02 00 03`
- observed V3 Pro USB profile-bank reads on June 16, 2026: DPI scalar/stage commands accepted storage IDs `0..5`, storage `2` and `3` matched the Bluetooth-created stored profiles, and lighting brightness storage `3` matched the Bluetooth-recreated target's `0x60` brightness
- observed V3 Pro USB physical profile-cycle behavior on June 16, 2026: each press emitted a passive HID hint pair on the `0x01:0x06`, `input=16`, `feature=1` interface (`04 00 ...` then `05 39 ...`), and effective storage/profile `0` moved first to stored bank `2` and then to stored bank `3`
- observed V3 Pro USB metadata reads on June 16, 2026: `0x05:0x88` with size `0x50` returned UUID/name chunks for slots `0x02..0x05`, including the same `OPENSNEK_RECREATE_SLOT_2` metadata previously read over Bluetooth and additional readable names `OS_P4_RENAMED` / `OS_P5`
- observed V3 Pro USB stored-bank changed-value writes on June 16, 2026: `0x04:0x05`, `0x04:0x06`, and `0x0F:0x04` round-tripped on profile `0x05` for DPI scalar, DPI stages, and all three brightness LED IDs, persisted across USB reconnect, then restored cleanly; cross-transport readback and power-cycle persistence remain pending
- observed V3 Pro USB profile delete/unassign on June 16, 2026: `0x05:0x03 02` removed profile `2` from the hardware cycle ring, so the next physical profile-cycle press skipped profile `2` and moved effective storage/profile `0` to stored profile `3`; the profile `2` settings/metadata bank remained readable
- observed V3 Pro USB direct active-profile reads on June 16, 2026: `0x05:0x84` changed from `03` to `01` and back to `03` across physical profile-cycle presses, while effective storage/profile `0` matched the reported active profile; `0x00:0x87` remained `02 32 03`
- observed V3 Pro USB active-profile selector on June 16, 2026: `0x05:0x04 01` and `0x05:0x04 03` ACKed and updated `0x05:0x84`; `0x05:0x04 02`, `04`, and `05` returned status `0x03` while leaving active profile `1` unchanged, even though those banks remained readable
- observed V3 Pro USB profile-summary candidates on June 16, 2026: early reads showed `0x05:0x80` returning a count-like value, `0x05:0x8A` returning max-bank hint `05`, and `0x05:0x81` returning `05 01 03 05`; later assignment/delete probes validated `0x05:0x81` as max profile ID followed by assigned profile IDs, while `0x00:0x87` remained stale summary telemetry
- observed V3 Pro USB metadata-write failure on June 16, 2026: an incomplete/incorrect `0x05:0x08` probe erased profile `0x05` metadata to UUID `ffffffff-ffff-ffff-ffff-ffffffffffff`, name `nil`, and disturbed settings. Settings were restored through validated DPI/lighting writes; later full-object chunks repaired metadata.
- observed V3 Pro USB create/name mapping negatives on June 16, 2026: before the complete object shape was mapped, `0x06:0x8E` returned stable profile-independent data (`00 64 00 04 c0 00 00 04 a8 00 00 00 15`), `0x05:0x82` rejected profile arguments, and `0x05:0x8A` ignored profile arguments
- observed V3 Pro USB bulk metadata mapping on June 16, 2026: `0x05:0x88` reads and `0x05:0x08` writes a 250-byte UUID/name/owner object using four full `0x50` chunks at offsets `0x0000`, `0x004b`, `0x0096`, and `0x00e1`. A direct full-object `0x05:0x08` repaired assigned profile `5` metadata and made `0x05:0x04 05` select it; direct `0x05:0x08` to unassigned profile `4` returned status `0x03`.
- observed V3 Pro USB create/inventory mapping on June 16, 2026: `0x05:0x02 04` followed by four full `0x05:0x08` chunks assigned profile `4`, changed `0x05:0x81` from `05 01 03 05` to `05 01 03 04 05`, changed `0x05:0x80` from count `3` to `4`, and made `0x05:0x04 04` select it. `0x05:0x03 04` and `0x05:0x03 05` removed those temporary assignments, leaving `0x05:0x81` as `05 01 03` and selectors `04`/`05` rejected again.
- observed V3 Pro USB create side effect on June 16, 2026: the `0x05:0x02` assignment path changed profile `4` DPI scalar/stage active token and brightness; OpenSnek restored them through `0x04:0x06`, `0x04:0x05`, and `0x0F:0x04`. Production USB create must rewrite desired profile content after metadata assignment.
- observed V3 Pro USB profile-management negative reads on June 16, 2026: BLE-like USB `03:80`, `03:82`, `03:84`, and `01:8C` did not expose BLE inventory/active/metadata behavior over the 90-byte HID feature-report transport
- observed V3 Pro USB static-color profile mapping on June 16, 2026: `0x0F:0x82`, size `0x0C`, read profile-addressed effect state for profile IDs `0..5` and LEDs `0x01`, `0x04`, and `0x0A`; assigned profile `2` accepted `0x0F:0x02` static-color writes and effective profile `0` mirrored those colors after `0x05:0x04 02`; the original profile `2` effect payloads were restored.
- shipped client behavior: OpenSnek exposes mapped core onboard profile CRUD through the shared Basilisk V3 USB configuration profile for the wired V3, V3 Pro, and V3 35K USB paths. The shared surface uses `0x05:0x81` inventory, `0x05:0x84` active-profile reads, guarded metadata/create/delete transactions, profile-addressed DPI/button/brightness/static-color/scroll-control writes, and passive profile-cycle HID refresh. OpenSnek also exposes volatile 14-cell V3-family Custom Frame software presets through service-owned `0x0F:0x03` streaming while it is running. Non-static onboard effect payload editing, macros, and advanced button families remain outside the v1 CRUD surface.

## Validated BT Profile (Basilisk V3 X HyperSpeed BT PID `0x00BA`, macOS stack)

Validated in-session over Bluetooth:
- HID path (`--disable-vendor-gatt`): probe works, config command reads return `None`, writes return `False`
- passive HID DPI report on the paired BT HID interface now drives immediate OpenSnek DPI-state updates; observed/app-supported frame prefixes include `05 05 02 <x_hi> <x_lo> <y_hi> <y_lo> ...` and the macOS-normalized `05 02 ...` variant
- Vendor GATT path (default-on): working for
  - idle-time raw read/write/readback
  - low-battery-threshold raw read/write/readback
  - lighting raw read/write/readback
  - battery vendor raw keys (`05 81 00 01`, `05 80 00 01`)
  - serial fallback (`01 83 00 00`)
  - device mode read fallback (`01 82 00 00`)
  - idle time fallback (`05 84 00 00` / `05 04 00 00`)
  - low battery threshold fallback (`05 82 00 00` / `05 02 00 00`)
  - button remap slots `0x01..0x05`, `0x09`, `0x0A`, `0x60`
- Vendor GATT button remap slot `0x06` returns error status (`0x03`) and is treated as a software-read-only Hypershift/sniper control on the current BLE path.
- `scroll-up-down-rebind.pcapng` confirms slot `0x09`/`0x0A` wheel-button mappings on BLE (`p0=0x0901` / `0x0A01`).
- `right-click-turbo.pcapng` confirms mouse turbo payloads on BLE (`action=0x0E`, slot `0x02`) with changing rate field.
- `basic-rebind.pcapng` includes a keyboard turbo-form payload (`action=0x0D`, key + rate fields).

`razer_ble.py` now uses vendor battery raw as BT fallback in `get_battery()` when vendor GATT is enabled.

## Validated BT Profile (Basilisk V3 Pro BT PID `0x00AC`, macOS stack)

Validated in-session over Bluetooth:
- vendor GATT path uses the same request headers and key catalog as the Basilisk V3 X HyperSpeed path, but the notify header is the shorter 8-byte variant and payload continuations may end with a short final fragment
- passive HID DPI reports are present on the paired BT HID interface with the same `05 05 02 <x_hi> <x_lo> <y_hi> <y_lo> ...` shape used by the validated V3 X Bluetooth path; a live macOS callback capture on `0x00AC` observed `900`, `2000`, and `1100` DPI stage frames
- working read/write/readback: DPI stages + active stage (`0B84`/`0B04`), sleep timeout (`05 84 00 00` / `05 04 00 00`), per-zone lighting brightness (`10 85 01 <led>` / `10 05 01 <led>`), per-zone static color (`10 83 00 <led>` / `10 03 00 <led>`)
- working read: battery raw (`05 81 00 01`), battery status (`05 80 00 01`)
- working write ACKs on tested BLE button-remap slots: `0x01..0x05`, `0x09`, `0x0A`, `0x34`, `0x35`
- observed V3 Pro Bluetooth button-layout shape now matches the shared Basilisk family on the tested slots, so OpenSnek ships the core buttons plus wheel-tilt controls on the BT profile
- observed V3 Pro Bluetooth wheel-tilt scroll blocks on 2026-04-03 after a working Synapse rebind: slot `0x34` / `0x35` read from BLE key `08 84 01 34` / `08 84 01 35` resolve to the raw function blocks `0e036800140000` / `0e036900140000`
- observed V3 Pro Bluetooth button-read packing on 2026-06-15: keys `08 84 01 0f` and `08 84 01 6a` return 16-byte duplicated-byte payloads that collapse to the clutch default block `06050501900190` and profile-button default block `12010100000000`
- shipped client behavior: OpenSnek now uses that same raw `0x0E` wheel-tilt block for Bluetooth `Scroll Left` / `Scroll Right` writes and for wheel-tilt default restore on the V3 Pro BT path
- observed V3 Pro Bluetooth lighting zone catalog: `10 80 00 01` -> `04 01 0a`, matching the validated zone map `scroll_wheel`, `logo`, `underglow`
- observed V3 Pro Bluetooth active-profile selector on June 16, 2026: `03 02 00 00` with payload `03` ACKed, changed `03 82 00 00` from `01` to `03`, and target `0` mirrored target `3`; payload `02` returned status `0x03` while target `2` was not in `03 80`; payload `01` restored active target `1`
- observed V3 Pro Bluetooth explicit-target create/name on June 16, 2026: target `5` was assigned through `03 06 05 00`, `08 05 05 00`, `01 8C 05 00`, `08 07 05 00`, `03 05 05 00`, full `03 04 05 00` metadata chunks, and stored DPI/brightness writes; `03 80` changed to `01 03 05`, `03 02` selected target `5`, and `03 84` read back the requested UUID/name
- observed V3 Pro Bluetooth metadata-write boundary on June 16, 2026: direct `03 04 05 00` metadata writes rejected with status `0x03` while target `5` was unassigned, but the same four-chunk metadata object succeeded after assignment and read back as a renamed profile; after `03 06 05 00`, inventory returned to `01 03` and target `5` selection rejected again while the stale bank remained readable
- shipped client behavior: OpenSnek exposes mapped core onboard profile CRUD on the validated V3 Pro Bluetooth path through `03 80` inventory, `03 82` active-target reads, guarded metadata/create/delete transactions, target-addressed DPI/button/brightness/static-color writes, and passive profile-cycle HID refresh. Macros, advanced button families, Synapse software-owned profile navigation, and profile-button remap writes remain outside the v1 CRUD surface.
- legacy lighting frame-color readback on `10 84 00 00` still does not return a usable payload on the V3 Pro path; OpenSnek now treats that frame family as legacy-only and uses the validated zone-state keys instead

Validation notes:
- the required hardware XCTest gate (`OPEN_SNEK_HW=1 swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests`) currently aborts under macOS TCC before CoreBluetooth can start in the unbundled test runner on this host
- the same five-step DPI stability sequence was rerun successfully through the bundled OpenSnek app/service host, and every step converged for three consecutive reads before restore

## Contributor-Validated BT Profile (Orochi V2 BT PID `0x0095`, macOS stack)

Validated by the PR contributor over Bluetooth:
- contributor-validated read: DPI stages + active stage returned `active=3`, `count=5`, and values `[400, 800, 1600, 3200, 6400]`
- contributor-validated profile behavior: scalar DPI range is capped at `18,000`, onboard profile count is `1`, and the profile declares no lighting effects, zones, or LED IDs
- contributor-validated battery behavior: vendor battery reads are used and the AAA-powered profile reports `charging = false`
- profile-mapped button layout: slots `0x01..0x05`, `0x09`, `0x0A`, and `0x60` are exposed from metadata, but Orochi-specific button-remap write/readback validation is still pending
- not shipped: 2.4 GHz HyperSpeed dongle path until its USB PID and protocol behavior are probed

## Validation Checklist

Per feature validation should include:
1. set operation ACK/success
2. read-back value match
3. persistence check after reconnect/power-cycle (when applicable)
4. behavior verification on hardware (button/scroll/lighting effects)

## References

- [USB Protocol](./USB_PROTOCOL.md)
- [BLE Protocol](./BLE_PROTOCOL.md)
- [BLE Reverse Engineering Notes](../research/BLE_REVERSE_ENGINEERING.md)
- OpenRazer driver protocol builders (`driver/razerchromacommon.c/.h`)
