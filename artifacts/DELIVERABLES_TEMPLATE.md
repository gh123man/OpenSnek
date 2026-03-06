# Deliverables template (fill after capture)

After completing captures and diff, fill this for the macOS/next agent session.

## 1. UUIDs
- **service_uuid:** 
- **write_char_uuid:** 
- **notify_char_uuid:** (if any)

## 2. Known commands (table)
| Operation | payload template (hex) | Variable bytes | Checksum rules |
|-----------|-------------------------|----------------|----------------|
| DPI write |                        |                |                |

## 3. Confirmed working DPI write payload (hex)
```
(value_hex from diff / replay success)
```

## 4. Raw logs
- baseline: `artifacts/baseline.json`, `artifacts/capture_baseline.log`
- dpi change: `artifacts/dpi_800_to_1600.json`, `artifacts/capture_dpi_800_to_1600.log`

## Replay command (example)
```bash
python ble_write_runner.py --target "<device-id>" --write-char "<char-uuid>" --payload "<hex>" --response
```
