# Basilisk V4 HyperSpeed local Bluetooth mapping

Date: 2026-11-08. Device: `BSK V4 HS`, `068E:00EC`. Base: `afe240d8`.
This directory contains local probe and app integration evidence, not Windows captures. See the [research report](../../../docs/research/BASILISK_V4_HYPERSPEED_BT.md)
for the command map, native button blocks, sources, and limitations.

| File | Evidence |
|---|---|
| `hid-identity.json` | Sanitized IORegistry identity/report descriptor |
| `gatt.txt` | Services/characteristics, standard battery 41%, PnP ID |
| `read-only.txt` | Initial DPI, lighting, power, profile and button inventory |
| `buttons-and-secondary-reads.txt` | All 12 button slots on targets 0/1, secondary DPI and lighting reads |
| `changed-write-restore.txt` | X/Y DPI, sleep, brightness changed/readback/restore; zone-effect mismatch and restore |
| `global-effect-and-buttons.txt` | Global-effect mismatch and restore; exited before button mutations |
| `all-buttons-app-pass.txt` | Final app-path remap, native Default, and exact original restore for all 12 slots on both targets |
| `remaining-buttons-write-restore.txt` | Follow-up left/right/middle/forward changed writes and exact full-payload restores on both targets |
| `button-write-restore.txt` | Eight slots changed to right-click and restored, both targets; final full baseline check |
| `dpi-stage-write-restore.txt` | Single/three-stage and active-ID edits, exact restore after each |
| `target-and-capability-reads.txt` | Additional lighting/profile/capability reads and rejected poll-rate candidates |
| `lighting-target-write-restore.txt` | Both live-target effect-write variants ACK without changing any of four readbacks; originals verified |
| `profile-metadata-reads.txt` | Metadata GET rejection on targets 0/1/2; payload contents excluded |
| `app-dpi-reliability.txt` | App bridge single/multiple-stage sequence passed; private recovery journal confirmed `restored` |
| `restored-baseline.json` | Final journal with device UUID omitted; all original mutable payloads, phase `restored` |

## Procedure and interpretation

Built the existing Swift probe with:

```sh
swift build --package-path OpenSnek --product OpenSnekProbe
```

Quit OpenSnek and its remaining process before vendor exchanges; its probe lease
enforced isolation. Read-only commands used the observed device name:

```sh
OpenSnek/.build/debug/OpenSnekProbe bt-raw-read --name 'BSK V4 HS' --key 0b840100 --timeout-ms 1500
OpenSnek/.build/debug/OpenSnekProbe bt-raw-read --name 'BSK V4 HS' --key 08800000 --timeout-ms 1500
```

For mutations, a temporary Swift session linked the existing `OpenSnekCore`,
`OpenSnekProtocols`, and `OpenSnekHardware` build objects. It discovered the exact
named device, then created `BLEVendorTransportClient(requiredPeripheralIdentifier:)`.
It held `BLEProbeSession`, checked that the app remained stopped before each
exchange, and saved original payloads and the immutable UUID in a private `0600`
journal **before any setting write**. No parallel vendor exchanges or command
retries were used. The temporary helpers are retained in this session's `/tmp`;
the on-wire requests and responses are preserved in these transcripts.

The initial effect tests deliberately stopped on changed-readback mismatch after
restoring the original body. Subsequent passes checked the existing journal's UUID
and complete baseline before doing more work. Each successful button test verified
both target 0 and target 1. The last pass verified all 20 original mutable reads
and four lighting-state views; final journal phase is `restored`. The private
recovery journal remains `/tmp/opensnek-bskv4-original-state.json`; its sanitized
copy here is evidence, **not a usable recovery target identifier**.

`READ`/`WRITE` lines in the temporary-session transcripts show the four-byte vendor
key, write data when present, matching-header status, and all raw notify frames.
The older probe formatter also attempts to label payload frames as notify headers;
only the frame matching the request ID is the status header. For example a payload
frame starting `03 05 ...` is DPI data, not an error response.

Results: **pass** for scoped DPI X/Y/count/active-ID, sleep, brightness, and eight
button changed/readback/restore checks. **Fail** for authoritative changed static
effect readback at all four tested addresses, despite successful ACKs. **Skipped**
for physical presses/rendering, power-cycle persistence, sleep/wake/reconnect,
charge transitions, and USB/receiver validation. The initial mapping pass made no app
behavior changes. The subsequent scoped integration passed
`HardwareDpiReliabilityTests.testBluetoothDpiStageApplyIsStableAcrossSequence`
on this device, including changed stage counts and original-state restore. Its
private journal is `/tmp/opensnek-bskv4-app-dpi-final-journal.json` (phase `restored`).

## Bluetooth button completion

The four remaining common slots (1, 2, 3, 5) passed changed-readback and exact
restore, pinned to the original peripheral UUID. The private journal
`/tmp/opensnek-bskv4-bt-remaining-buttons.json` completed in phase `restored`.
Together with the original eight-slot pass this covers the full twelve-slot
inventory. Physical special-button labels remain inferred from native actions and
the official Razer layout, rather than press-correlated.

The first two full app-path attempts failed and their initial restore attempts
also failed; both journals were then recovered successfully using the UUID-pinned
recovery mode. `all-buttons-app-initial-failure.txt`, `all-buttons-app-recovery.txt`,
`all-buttons-app-diagnostic-failure.txt` and `all-buttons-app-diagnostic-recovery.txt`
preserve those outcomes. Diagnostics observed an empty response from a button GET,
followed by malformed/busy notifications during restore. Read-only request-ID
boundary checks (`request-id-boundary-reads.txt`) all returned valid headers.

The transport previously allowed its 120 ms idle timer to return success with zero
notifications after an ATT write acknowledgement. It now leaves the overall
exchange timeout active until a response arrives. No write/read retry was added.

With that transport correction, the full `HardwareBasiliskV4BluetoothButtonTests`
app-path sequence passed for all twelve slots: changed mapping, native Default,
and exact original payload restoration on both targets. See
`all-buttons-app-pass.txt`. The private journal
`/tmp/opensnek-bskv4-bt-all-buttons-final.json` ended in phase `restored`.
This finite pass does not establish endurance, physical press behavior, or
power-cycle persistence.
