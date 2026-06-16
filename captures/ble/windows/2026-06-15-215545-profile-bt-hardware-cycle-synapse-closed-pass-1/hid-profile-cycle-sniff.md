# HID Profile Cycle Sniff

Context: Basilisk V3 Pro connected over Bluetooth, Synapse closed, physical
profile button pressed three times during/after the BTVS pass. The user
confirmed the bottom LED advanced.

The sniff opened the non-pointer/non-keyboard Bluetooth HID collections exposed
by hidapi and read input reports for 20 seconds.

```text
bt_hid_paths 4
opened BSK V3 PRO usage_page 12 usage 1
opened BSK V3 PRO usage_page 1 usage 128
opened BSK V3 PRO usage_page 1 usage 0
opened BSK V3 PRO usage_page 1 usage 0
   3.316s usage_page=1 usage=0 len=9 hex=040400000000000000
   3.517s usage_page=1 usage=0 len=9 hex=050539000000000000
   5.354s usage_page=1 usage=0 len=9 hex=040400000000000000
   5.557s usage_page=1 usage=0 len=9 hex=050539000000000000
   7.343s usage_page=1 usage=0 len=9 hex=040400000000000000
   7.546s usage_page=1 usage=0 len=9 hex=050539000000000000
reports 6
```

Interpretation:

- Each physical profile-button press produced two 9-byte passive HID reports.
- The first report was `04 04 00 00 00 00 00 00 00`.
- The follow-up report was `05 05 39 00 00 00 00 00 00`, about 200 ms later.
- These reports are a profile-cycle hint, not a decoded target/profile ID.
- OpenSnek should use them to trigger an immediate debounced, one-shot live
  target `1` fingerprint refresh, then match that live state against known
  onboard profile snapshots. This avoids continuous current-profile polling
  while still updating the UI reactively.
