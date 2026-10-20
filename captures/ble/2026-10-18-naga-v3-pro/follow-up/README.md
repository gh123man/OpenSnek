# Naga V3 Pro gap-validation follow-up (2026-10-18)

Contributor validation by owner [jpagh](https://github.com/jpagh), using the same
`068E:00E9` Naga V3 Pro over Bluetooth. Both OpenSnek app and service processes
were stopped throughout the isolated checks. No command retries were used.
The owner's separate Naga Pro mappings were not touched.

## Power-cycle persistence is setting-specific

The harness captured all four original settings before any writes, journaled the
baselines, then changed and read back each setting. With OpenSnek still stopped,
the owner switched the mouse off for approximately ten seconds and reconnected
in Bluetooth mode. All four post-cycle reads completed before any restore writes,
so neither app auto-restore nor a restore command masked the result.

| Setting / key | Original | Temporary value | After power cycle |
| --- | --- | --- | --- |
| DPI stages `0B 84/04 01 00` | Active stage `1600x1600` | `1700x1800` | Temporary value persisted; IDs, active token, and 50K tail stage unchanged |
| Sleep timeout `05 84/04 00 00` | 60 s | 120 s | 120 s persisted |
| Wheel brightness `10 85/05 01 01` | 85 | 86 | 86 persisted |
| Live wheel static state `10 83/03 00 01` | Green `#00FF00` | `#112233` | Reverted to original green |

Evidence: [persistence-transcript.txt](persistence-transcript.txt) and
[persistence-state.json](persistence-state.json). After observing the result, the
harness restored and asserted byte-exact originals for all four settings.

This closes the previously untested persistence question for these settings on
one power cycle: DPI stages, sleep timeout, and the persistent-target brightness
survived, while the live-target static color did not. It does **not** prove
persistence for every effect, zone, button binding, or repeated cycle. Use
restore-on-connect when the live color must be reapplied; this is an observation
of the existing command targets, not a new persistence implementation.

## All 33 Bluetooth button slots: changed writes on both targets

The known USB `02:84` inventory supplies 33 slot IDs. Before any writes, the
harness captured the current seven-byte even/live function-block lane on both
BLE targets `00` and `01` for every slot: **66 baseline blocks**. It did not assume
factory defaults or reset the mouse.

For each slot and target independently, the harness:

1. Journaled the slot, target, temporary block, and original blocks before writing.
2. Temporarily wrote a keyboard F24 block (`02 02 00 73 00 00 00`; F23 if already
   identical) and asserted changed readback on the requested target.
3. Restored the persistent target first, then the live target, and asserted both
   originals. Restoring live last avoids a persistent write projecting into live
   and overwriting an intentionally different live binding.
4. Only then moved to the next target or slot.

**All 66 changed-write checks passed.** Afterward, a fresh full 66-block read
matched the initial snapshot exactly. Snapshot/journal and per-target pass list:
[all-buttons-state.json](all-buttons-state.json). Full command/notify evidence:
[all-buttons-transcript.txt](all-buttons-transcript.txt).

Slots exercised:

```text
1,2,11,12,14,3,52,53,106,57,128,66,65,64,69,68,67,72,71,70,75,74,73,80,81,82,83,84,85,5,4,9,10
```

This is exhaustive write/readback/restore for the **33 shipped slots**, not a
blind scan of every possible slot ID, discovery of a BLE inventory command, or
physical press validation of all 33 controls in this pass.

## Six-button plate: physical labels verified

The captured original blocks on both targets map slots `80...85` to keyboard
HID usages `1E...23` (digits `1...6`). After restoration, the owner fitted the
six-button plate, focused the chat input, and physically pressed its printed
labels **1, 2, 3, 4, 5, 6** in label order. No temporary mappings were needed.

Owner response:

> 123456 (they wrap the same with the labels as the other naga 6 panel and I pressed them in label order)

This independently confirms label `1` → slot `80`, through label `6` → slot `85`,
including the physical wrapping, on this V3 Pro rather than merely inheriting the
Naga V2 Pro's mapping. There is no button-order code change because the shipped
mapping was already correct.

## Remaining limits

- BLE poll-rate and onboard-profile CRUD mappings remain unvalidated/unexposed.
- Wheel mode/responsiveness setting commands need evidence such as a Windows
  Synapse capture; factory-button remapping is not a decoded setting API.
- Custom software-lighting frames were not part of these quick checks.
- Charging-status interpretation and independent battery calibration are not
  established by these tests; BLE charging stays unknown without USB fallback.
- Approximately two-minute idle/wake and one power cycle do not establish
  long-duration reliability or universal persistence.
