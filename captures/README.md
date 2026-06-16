# Capture Corpus

This directory stores BLE protocol captures used to derive and validate `tools/python/razer_ble.py` behavior.

## Layout

- `ble/filteredcap.pcapng`
  - First broad Synapse BLE capture.
  - Established vendor write/notify framing:
    - write handle `0x003d` (`...1524`)
    - notify handle `0x003f` (`...1525`)
    - request-id echo and status-byte ACK model.
  - Source for generic read/write framing and key-byte model (`byte4..7`).

- `ble/power-lighting.pcapng`
  - Focused capture for scalar settings.
  - Confirms raw power/sleep/lighting key pairs and payload sizes:
    - power timeout: `05 84` / `05 04` (u16)
    - sleep timeout: `05 82` / `05 02` (u8)
    - lighting value: `10 85` / `10 05` (u8)
    - lighting frame stream: `10 04` with 8-byte payload `04 00 00 00 [M][R][G][B]`
  - Confirms two-stage scalar read response pattern:
    - notify header (length/status), then
    - payload notify carrying scalar bytes.

- `ble/all-lighting-modes.pcapng`
  - Full Synapse lighting-mode walkthrough (effects + color changes).
  - Confirms:
    - dominant frame stream key `10 04` with `04 00 00 00 [M][R][G][B]`
    - mode selector write key `10 03` with payload `08 00 00 00`
  - Used to add BT frame-color and mode-raw APIs in `tools/python/razer_ble.py`.

- `ble/all-key-binding-functions.pcapng`
  - Attempted full single-button binding walkthrough in Synapse.
  - Observed repeated writes for slots `0x05` and `0x04` only:
    - header: `08 04 01 <slot>`, len `0x0a`
    - payload: `01 <slot> 01 00 0000 0000 0000`
  - This adds capture-backed evidence for layer-specific clear/default entries (`layer=0x01`, `action=0x00`).
  - No distinct turbo/media/macro payload variants were present in this trace.

- `ble/basic-rebind.pcapng`
  - Button remap workflow across multiple slots.
  - Confirms two-step write flow:
    - header select `op=0x0a`, key `08 04 01 <slot>`
    - 10-byte action payload write.

- `ble/right-click-bind.pcapng`
  - Focused slot `0x02` (right-click) transitions.
  - Confirms payloads for left-click remap, keyboard remap, and explicit right-click restore.

- `ble/right-click-turbo.pcapng`
  - Focused slot `0x02` turbo workflow for right-click.
  - Confirms turbo action payload family on BLE:
    - `01 02 00 0E 0301 8E00 0000`
    - `01 02 00 0E 0301 3E00 0000`
  - Synapse also emits slot `0x05`/`0x04` layer-clear housekeeping writes in the same apply sequence.

- `ble/hyper-shift-left-click-defualt.pcapng`
  - Additional remap workflow capture targeting hypershift-related UI flow.
  - Reconfirms Synapse writes for slots `0x04` and `0x05` using:
    - header: `08 04 01 <slot>`, len `0x0a`
    - payload: `01 <slot> 01 00 0000 0000 0000`

- `ble/hypershift-bind.pcapng`
  - Focused "hypershift bind -> right click -> default" walkthrough.
  - Vendor writes are capture-identical to `hypershift-full-hid.pcapng`:
    - slot `0x05`: `01 05 01 00 0000 0000 0000` (layer-clear)
    - slot `0x04`: `01 04 01 00 0000 0000 0000` (layer-clear)
    - slot `0x02`: `01 02 00 01 0102 0000 0000` (right click / slot-2 default)
  - No selector for slot `0x06` appears.
  - Follow-up runtime probe: direct slot `0x06` writes on `08 04 01` return error status (`0x03`).

- `ble/hypershift-full-hid.pcapng`
  - Same vendor writes as `hypershift-bind.pcapng`, but includes unfiltered HID notifies.
  - Additional HID notify stream observed on handle `0x002b` with constant 8-byte payload:
    - `05 10 00 00 00 00 00 00`
  - No extra vendor config key beyond `08 04 01 <slot>` appears in this trace.
  - No host ATT write for a slot-`0x06` button-bind command is present.

- `ble/dpi-cycle-left-click-default.pcapng`
  - Focused capture for DPI-cycle control rebinding.
  - Confirms writable slot `0x60` on the same button-bind key family.
  - Observed transitions:
    - left-click payload: `01 60 00 01 0101 0000 0000`
    - restore/default payload: `01 60 00 06 0106 0000 0000`

- `ble/scroll-up-down-rebind.pcapng`
  - Focused capture for wheel-button binding transitions.
  - Confirms BLE writable slots `0x09` (scroll-up button) and `0x0A` (scroll-down button).
  - Observed transitions:
    - slot `0x09`: `01 09 00 01 0101 0000 0000` (left click) <-> `01 09 00 01 0109 0000 0000` (scroll up)
    - slot `0x0A`: `01 0A 00 01 0101 0000 0000` (left click) <-> `01 0A 00 01 010A 0000 0000` (scroll down)
  - As with other bind captures, Synapse also emits slot `0x05`/`0x04` layer-clear housekeeping writes and slot `0x02` explicit right-click restore.

- `ble/vendor-key-sweeps-2026-03-08.md`
  - In-session automated BLE vendor key sweep report.
  - Documents confirmed mappings, candidate keys, and safety findings from read/writeback probing.

- `ble/windows/2026-06-15-192730-profile-button-cycle-pass-1/`
  - Windows BTVS/tshark capture of a Basilisk V3 Pro Bluetooth physical profile-cycle action while Synapse was connected.
  - Confirms that the automated BTVS TCP capture path records the same vendor ATT handles:
    - write handle `0x003d`
    - notify handle `0x003f`
  - Captures Synapse profile-projection traffic that is not present in a same-host idle baseline, including:
    - `01 86 00 00` read returning `00 00 00`
    - `01 82 00 00` read returning `03 00`
    - `01 8C <target> 00` reads returning `01` for observed stored/profile targets
    - `08 04 04 0F` and `08 04 01 0F` writes for slot `0x0F` across profile/layer targets
    - DPI table writes/reads on `0B 04 01 00` / `0B 84 01 00`
  - This is research evidence for the Basilisk V3 Pro BT profile model, not shipped OpenSnek protocol support yet.

- `ble/windows/2026-06-15-192930-idle-baseline-pass-1/`
  - Windows BTVS/tshark idle baseline on the same host/session.
  - Only observed periodic `10 04 00 00` lighting-frame writes over the 15-second window.
  - Used to separate background lighting chatter from profile-cycle/projection traffic in the profile-button pass.

- `ble/windows/2026-06-15-195434-profile-button-cycle-focused-pass-4/`
  - Longer Windows BTVS/tshark physical profile-cycle capture with matching Synapse log events.
  - Synapse logged `razerKey key 80` as `disable` for `flag:0` and `navigateProfile` / `CycleUp` for `flag:1`.
  - The wire trace captured repeated projection bursts after profile cycling, including:
    - `01 86 00 00` reads returning `00 00 00`
    - `01 82 00 00` reads returning `03 00`
    - `01 8C <target> 00` reads returning `01`
    - profile/apply candidate writes on `08 05`, `08 06`, and `08 07`
    - live DPI projection through `0B 04 01 00` followed by `0B 84 01 00` readback
    - button projection into stored/profile targets and live target/layer `1` through `08 04 <target> <slot>`
  - This is the preferred physical-button profile-switch capture for future profile-switch spec work.

- `ble/windows/2026-06-15-202616-profile-inventory-read-path-pass-1/`
  - Windows BTVS/tshark capture of selecting existing Basilisk V3 Pro Bluetooth profiles in Synapse without editing settings.
  - Synapse logged five `from actionFromUI newActiveProfileGUID` / `set active profile` transitions:
    - `49277292-1bea-4673-9ed9-5d91113c8cbc` (`BRIAN-DESKTOP-Default`)
    - `26a33407-4094-469b-b3b1-f3caae38693b` (`Brian's MacBook Pro (2)-Default`)
    - `18f2a4cc-ecb8-4765-b532-9df401a686d6` (`OS_P5`)
    - `27530668-c3e2-4e0a-a06e-a4854383c4e9` (`OS_P4_RENAMED`)
    - `cbb11d67-38cd-46db-bc16-a95424aaee61` (`OPENSNEK_CAPTURE_1`)
  - Confirms that Synapse profile selection is active projection rather than passive inventory read. The wire trace shows DPI and button projection onto live target `1`, with stored/profile target candidates such as `08 04 02 04` and `08 04 03 05` appearing alongside live `08 04 01 <slot>` writes.
  - This capture backs the draft implementation model in `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-203420-profile-create-disposable-pass-1/`
  - Windows BTVS/tshark capture of creating one disposable Basilisk V3 Pro Bluetooth profile in Synapse.
  - Synapse created GUID `a5c15916-b5fd-4f33-8408-d978cd3bf37c`, first as `BRIAN-DESKTOP-Default 1`, then with user-supplied name `OPENSNEK_CREATE_PROBE_1`.
  - Synapse mapped the new profile to OBM/profile target `2` and logged `obmEngineMouse.addProfile() profileId:2`.
  - The wire trace shows the first capture-backed stored-profile create sequence:
    - `03 06 02 00`
    - `08 05 02 00`
    - `01 8C 02 00`
    - `08 07 02 00`
    - `03 05 02 00`
    - chunked metadata writes on `03 04 02 00`
    - stored target DPI writes on `0B 01 02 00` and `0B 04 02 00`
    - stored target brightness write on `10 05 02 00`
  - Later live macOS stored-only probes confirmed target-scoped V3 Pro lighting
    readback/write shapes: brightness writes use `10 05 <target> 00` and read
    back through `10 85 <target> <led>`; static color writes use
    `10 03 <target> <led>` and read back through `10 83 <target> <led>`.
    Advanced/effect payloads remain unmapped.
  - This capture is the source for the create section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-204312-profile-update-active-button-pass-1/`
  - Windows BTVS/tshark capture of updating Button5 on the active disposable profile `OPENSNEK_CREATE_PROBE_1`.
  - Synapse logged the active profile GUID `a5c15916-b5fd-4f33-8408-d978cd3bf37c` and profile ID `2`.
  - The capture contains two button edits, both with the same two-write shape:
    - stored target write: `08 04 02 05`
    - live projection write: `08 04 01 05`
  - No profile metadata rewrite (`03 04`), DPI write, lighting write, `08 05`, `08 07`, or `01 8C` operation was present in the reduced button-update windows.
  - This capture backs the active-profile button update section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-204849-profile-rename-only-pass-1/`
  - Windows BTVS/tshark capture intended to rename the active disposable profile from `OPENSNEK_CREATE_PROBE_1` to `OPENSNEK_RENAME_PROBE_1`.
  - Synapse logged the active profile with the renamed display name at `+8.574s`.
  - The vendor stream contained only periodic `10 04 00 00` lighting-frame writes; no `03 04` metadata rewrite or other non-lighting vendor operation was present.
  - Treat as rename evidence with timing caveat; pass 2 provides the clearer no-rename-write observation.

- `ble/windows/2026-06-15-205102-profile-rename-only-pass-2/`
  - Windows BTVS/tshark capture where a different Synapse profile was renamed because renaming the assigned disposable profile removed it from the assigned-slot UI.
  - Synapse logged profile `cbb11d67-38cd-46db-bc16-a95424aaee61` as `OPENSNEK_CAPTURE_1`, then as `OPENSNEK_CAPTURE_1_foo` at `+12.995s`.
  - No non-lighting vendor operation occurred near the rename event.
  - The only non-lighting operations were profile-selection/button projection writes on `08 04 01 05`, `08 04 03 05`, and `08 04 01 04`.
  - This capture backs the rename section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-205659-profile-slot-unassign-none-pass-1/`
  - Windows BTVS/tshark capture of replacing an assigned saved/onboard profile slot with `None`.
  - Synapse logged `obmEngineMouse.deleteProfile(3)`, `profileIdList":[1,4,5,2]`, and `numOfProfiles":4`.
  - The pcap contains buffered BTVS packets from before `metadata.json` `captureStart`; filtering by absolute wall-clock capture time leaves exactly one non-lighting vendor operation in the real capture window.
  - The in-window operation is `03 06 03 00` with empty payload and success status `02`.
  - This capture backs the delete/unassign section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-210321-profile-active-slot-unassign-cycle-pass-1/`
  - Windows BTVS/tshark capture of replacing active saved/onboard target `2` with `None`, then pressing the physical profile button.
  - Synapse logged `obmEngineMouse.deleteProfile(2)`, `profileIdList":[1,4,5]`, and `numOfProfiles":3`.
  - The delete operation is `03 06 02 00` with empty payload and success status `02`.
  - The delete itself did not immediately project a replacement profile to live target `1`.
  - Subsequent physical profile-button presses were handled by Synapse as software `navigateProfile` events. With Synapse open, that path appears to cycle a hybrid host profile list containing local/Synapse profiles and on-device-backed profiles, and it can still select stale host profiles not present in the OBM `profileIdList`.
  - This capture backs the active-delete and Synapse stale-host-cycle caveat in `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-212318-profile-active-saved-slot-dpi-update-pass-1/`
  - Windows BTVS/tshark capture intended to update one DPI stage on the active saved/onboard profile.
  - The action was noisy: the user switched profiles and changed DPI several times, so this capture is treated as traffic-shape evidence rather than a clean single-operation proof.
  - Synapse performed an early stored target `2` add/rewrite that included `03 04 02 00` metadata chunks, `0B 01 02 00`, and `0B 04 02 00` with a stored DPI table of `400`, `800`, `1600`, `3200`, `6400`.
  - Later DPI edits/projections in the capture used live target `1` via `0B 04 01 00`, including observed tables with edited stages `7150` and `5250`.
  - This capture backs the noisy active saved-slot DPI update caveat in `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-213027-profile-active-saved-slot-dpi-update-clean-pass-1/`
  - Windows BTVS/tshark capture of updating one DPI stage on the active saved/onboard profile `Brian's MacBook Pro (2)-Default`.
  - Synapse identified GUID `26a33407-4094-469b-b3b1-f3caae38693b` with `"obmSlotId":[2]`.
  - The actual DPI edit changed stage 1 from `400` to `7650` and changed the active stage token from `2` to `1`.
  - The BLE write was live-only: `0B 04 01 00` with table `7650`, `800`, `1600`, `3200`, `6400`, followed by `0B 84 01 00` readback. No `0B 04 02 00` stored-target DPI table write occurred in this pass.
  - This capture backs the active saved-slot DPI update section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-213442-profile-inactive-saved-slot-button-update-pass-1/`
  - Windows BTVS/tshark capture intended to update one button on an inactive saved/onboard profile.
  - The action was invalid for button mapping because the user changed DPI by mistake.
  - Synapse switched/projected `OS_P5` and emitted a live target `1` DPI table write; this capture is retained as an informational mis-action trace and should not be used as button-update evidence.

- `ble/windows/2026-06-15-213655-profile-inactive-saved-slot-button-update-pass-2/`
  - Windows BTVS/tshark capture of a Button5 keyboard assignment intended for a saved/onboard slot that was not meant to be live.
  - Synapse logged `setSingleButtonMapping profileId: 5` for Button5 -> keyboard HID `0x09`.
  - The wire trace wrote stored target `5` first (`08 04 05 05`, payload `05 05 00 02 02 00 09 00 00 00`), then live target `1` (`08 04 01 05`, payload `01 05 00 02 02 00 09 00 00 00`).
  - No profile metadata rewrite, add/delete, profile-apply, DPI table write, or brightness write occurred in the in-window operation.
  - This capture backs the attempted inactive saved-slot button update section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-214111-profile-inactive-saved-slot-dpi-update-pass-1/`
  - Windows BTVS/tshark capture intended to update one DPI stage on an inactive saved/onboard profile.
  - Synapse selection made the edited profile live first: GUID `27530668-c3e2-4e0a-a06e-a4854383c4e9`, name `OS_P4_RENAMED`.
  - The BLE traffic used live target `1` only:
    - selection/activation projection: `0B 04 01 00`, table `400`, `800`, `1600`, `3200`, `6400`, active token `3`
    - DPI edit: `0B 04 01 00`, table `400`, `6300`, `1600`, `3200`, `6400`, active token `2`
    - revert/projection: `0B 04 01 00`, table `400`, `800`, `1600`, `3200`, `6400`, active token `2`
  - No stored-target DPI table write (`0B 04 <stored-target> 00`) occurred.
  - This capture backs the attempted inactive saved-slot DPI update section of `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-214518-profile-synapse-closed-physical-cycle-pass-1/`
  - Windows BTVS/tshark capture of pressing the physical profile button after Synapse closed/crashed.
  - The capture has no decoded BLE vendor writes or notify responses and no matching Synapse events.
  - User observation after follow-up checks: Bluetooth and USB both support hardware/onboard profile-button cycling when Synapse is not taking over the device.
  - When connected to Synapse, both transports appear to have the physical profile button intercepted as software navigation; on USB, the bottom LED no longer responds in that Synapse-owned state.
  - OpenSnek should prefer firmware/onboard profile cycling by default and treat Synapse's software takeover as a vendor UI behavior, not the target model.
  - This capture backs the Synapse-closed Bluetooth physical-cycle note in `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`.

- `ble/windows/2026-06-15-215545-profile-bt-hardware-cycle-synapse-closed-pass-1/`
  - Windows BTVS/tshark capture of three Basilisk V3 Pro Bluetooth physical profile-button presses with Synapse closed.
  - User confirmed the bottom LED advanced during the pass, so the mouse performed firmware/onboard profile cycling.
  - Absolute timestamp filtering shows the decoded vendor reads in `summary.md` were buffered/stale frames from before `captureStart`; no in-window BLE vendor profile-cycle write/read/notify identified the new active profile.
  - BTVS showed in-window malformed/short notifications on handle `0x001b` clustered near the button activity, but without exposed payload bytes.
  - A companion Windows HID sniff observed two 9-byte passive reports per physical press on the Bluetooth HID collection with usage page `0x01`, usage `0x00`: `04 04 00 00 00 00 00 00 00`, then about 200 ms later `05 05 39 00 00 00 00 00 00`.
  - Use those HID reports as profile-cycle refresh hints only. Later live macOS probing found `03 82 00 00` is the direct active target read; the captured `0B 82 00 00` hardware-active DPI surface remains useful as validation/fallback, while live target `1` reads are not reliable for firmware-ring identity.
  - This capture backs the firmware-first Bluetooth profile-cycle hint notes in `docs/protocol/BLE_PROFILE_CRUD_SPEC.md` and `docs/protocol/BLE_PROTOCOL.md`.

- `ble/windows/2026-06-15-222336-profile-cycle-event-driven-followup-read/`
  - Windows event-driven HID/Bleak probe of the Basilisk V3 Pro Bluetooth profile button with Synapse closed.
  - Added `tools/python/bt_profile_cycle_watch_windows.py` to listen for passive HID profile-cycle hints and issue one BLE vendor follow-up read per debounced hint.
  - The 3-press pass saw the expected `04 04 ...` / `05 05 39 ...` hint pairs and issued one `0B 84 01 00` read after each hint.
  - The 1-press delayed pass waited 2 seconds after the hint and read both `0B 84 01 00` and `08 84 01 04`.
  - In both passes, the known live-target readback values stayed unchanged even though the HID hints fired; this rules out those keys as a reliable active firmware-ring profile identity source.
  - This capture backs the guidance to use passive HID hints for event-driven refresh/stale marking, and rules out `0B 84 01 00` / `08 84 01 04` as reliable firmware-ring identity sources.

- `ble/windows/2026-06-15-225000-profile-active-target0-dpi-surface/`
  - Windows read-only BLE DPI-family probes for Basilisk V3 Pro Bluetooth hardware profile cycling.
  - User clarified slot terminology: slot `0` is live/current; slots `1..4` are non-live onboard slots.
  - The sweep found that `0B 81/82/83 00 00` expose the hardware-active DPI scalar/stage-list/stage-token surface.
  - Stored slot `1` maps to BLE target `2` and returned the random table `3200, 10200, 1600, 7900, 1100`.
  - Stored slot `2` maps to BLE target `3` and returned the mostly-100 table `100, 100, 100, 100, 800`.
  - The `profile-cycle-active-target0-short` pass showed `0B 82 00 00` move from the target-`2` random table to the target-`3` mostly-100 table after one hardware profile-button cycle.
  - The later slot2-to-slot3 pass did not change active target `0`; the user clarified only slots `1` and `2` were intentionally mapped, so treat slots `3`/`4` as unmapped in this setup.
  - This capture backs the DPI-fingerprint fallback model: HID hint detects the change, then `0B 82 00 00` can identify the active profile by matching active DPI stages against stored slot tables when those tables are unique. Later live macOS probing supersedes this as the primary path with `03 82 00 00` direct active-target reads.
  - Later live macOS stored-only update validation extended target `0` beyond
    DPI: after cycling to target `3`, `08 84 00 <slot>`, `10 85 00 <led>`, and
    `10 83 00 <led>` mirrored target `3` button and lighting state while target
    `1` retained the previous live/projection values.
  - Live delete validation on target `3` showed `03 06 03 00` removes that
    target from `03 80` inventory but does not immediately erase metadata or
    setting banks. If the deleted target is active, `03 82` can keep returning
    it until the next profile-cycle press, after which firmware skips it.

- `ble/windows/2026-06-15-224531-profile-synapse-startup-takeover-pass-1/`
  - Windows BTVS/tshark capture of launching Synapse/AppEngine while the Basilisk V3 Pro was connected over Bluetooth.
  - The pcap contains some buffered/stale BTVS traffic before the wrapper's wall-clock `captureStart`; `analysis.md` filters to the actual capture window.
  - In-window startup traffic did not include an `08 04 <target> 6A` profile-button binding write.
  - In-window startup traffic includes the strongest read-side onboard profile candidates so far: `03 80 00 00` returned target list `01 02 03`, followed by `03 84 02/03 00` metadata chunk reads.
  - Synapse did read `08 84 <target> 6A` for live/stored targets and performed live target apply/projection traffic (`08 05 01 00`, `08 07 01 00`, `08 06 01 00`, `0B 04 01 00`) as it loaded the selected software profile.
  - Current interpretation: Synapse's software takeover is likely host event ownership or a side effect of the live apply/projection sequence, not a simple profile-button remap write.
  - This backs the firmware-first OpenSnek guidance: do not copy Synapse startup takeover behavior for profile monitoring.

## Notes

- Captures are intentionally action-scoped for faster diffing.
- Keep new captures in `captures/ble/` and add an entry here with what changed and what was validated.


## Capture Guide

### Windows Automated BTVS Capture

Use the repo wrapper when BTVS is installed under `C:\BTP\v1.14.0` and Wireshark is installed under `C:\Program Files\Wireshark`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows\capture-btvs.ps1 -Name profile-button-cycle-pass-1 -Seconds 25
```

Run it from the repository root. The script creates a timestamped output folder under `captures\ble\windows\`, for example:

```text
captures\ble\windows\2026-06-15-195434-profile-button-cycle-focused-pass-4\
```

Typical capture flow:

1. Make sure the mouse is connected over Bluetooth and Synapse is open.
2. Start with a short idle baseline when the current background traffic is unknown:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\windows\capture-btvs.ps1 -Name idle-baseline -Seconds 15
   ```

3. Start the feature capture:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\windows\capture-btvs.ps1 -Name profile-switch-button-pass-1 -Seconds 45
   ```

4. As soon as the script prints `Capturing BTVS TCP stream`, perform only the target action. For a profile-switch button pass, press the physical profile switch button a few times with a couple seconds between presses.
5. Leave the mouse alone until capture completes.
6. Inspect the generated files in the order below, starting with `synapse-events.md`.

Useful options:

- `-Seconds <n>`: capture duration. Use `15` for idle baselines, `30..60` for focused feature passes.
- `-Name <name>`: short action-based label used in the output folder name.
- `-CorrelationWindowSeconds <n>`: widen or narrow Synapse-to-packet matching. Default is `3`.
- `-NoSynapseLogs`: skip Synapse log export when Synapse is intentionally not running.
- `-ShowBtvs`: leave the BTVS window visible while capturing.
- `-KeepBtvs`: leave a BTVS instance started by the script running after capture.
- `-ReuseBtvs`: attach to an existing listener on the requested port. Prefer the default fresh-port behavior unless intentionally reusing BTVS.
- `-BtpRoot <path>` / `-WiresharkRoot <path>`: override tool locations when BTVS or Wireshark are installed somewhere else.

The script:

- starts BTVS in remote Wireshark mode when no sniffer is already listening on the requested port
- uses the requested port when free, or automatically picks the next free port when an old BTVS listener is already present
- captures from `TCP@127.0.0.1:<port>` with `tshark`
- writes packet artifacts:
  - `capture.pcapng`
  - `att.csv`
  - `vendor-att.csv`
  - `summary.md`
- writes capture/log correlation artifacts by default:
  - `metadata.json`
  - `synapse-events.csv`
  - `synapse-events.md`
  - `correlation.md`

The default vendor handle filter is:

```text
btatt.handle == 0x003d || btatt.handle == 0x003f || btatt.handle == 0x0040
```

BTVS is a GUI sniffer; its documented command-line options do not include a headless mode. The wrapper starts it with a hidden window and tries to stop the helper process after capture, but some Windows installs self-elevate BTVS and reject non-elevated termination. If cleanup is denied, close the hidden/visible BTVS window manually or run the wrapper from an elevated PowerShell session so the script can terminate the helper process.

By default the wrapper avoids reusing an already-listening BTVS port, because long-running BTVS sessions can include buffered or stale packets. Use `-ReuseBtvs` only when intentionally attaching to an existing listener.

For feature discovery, open files in this order:

1. `synapse-events.md` to identify what Synapse thought happened
2. `correlation.md` to jump to nearby non-lighting vendor operations
3. `summary.md` for the full grouped vendor exchange list
4. `capture.pcapng` only when the summaries are ambiguous

Recommended feature-mapping loop:

1. Capture a short idle baseline in the same Synapse/device session when background traffic is unknown.
2. Capture the smallest action sequence that exercises one feature.
3. Treat keys present in both the idle baseline and action capture as background candidates.
4. Use `correlation.md` to inspect non-lighting vendor operations near Synapse feature events.
5. Record only capture-backed interpretations in protocol or research docs, and leave uncertain keys marked research-only.

Some BTVS runs can include buffered packets from before the wrapper's recorded
`captureStart`. If a capture's `frame.time_relative` exceeds the requested
duration or correlation looks too broad, filter packet operations by
`metadata.json` `captureStart`/`captureEnd` using `frame.time_epoch` before
making protocol claims.

Use `-NoSynapseLogs` only for captures where Synapse is intentionally not running. Use `-CorrelationWindowSeconds <seconds>` when Synapse log timestamps and BTVS packet times need a wider or narrower matching window.

### Older Manual Wireshark Flow

If the automated wrapper is unavailable:

1. Install BTVS.
2. Launch BTVS. It will open Wireshark.
3. Apply this display filter to hide the noisy HID traffic and keep the ATT exchange visible:

```text
btatt && btatt.handle != 0x002b && btatt.handle != 0x001b
```

4. Open Synapse.
5. Perform the smallest action sequence that reproduces the behavior you want to capture.
6. In Wireshark, export only the relevant packets:
   `File -> Export Specified Packets`
7. Save the capture under `captures/ble/` with a short action-based name, then add a short note to this README describing what the trace validates.
