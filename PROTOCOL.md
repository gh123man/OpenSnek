# Razer Protocol Documentation Index

The USB and BLE protocols are related at the **setting semantics** level (DPI stages, battery, poll-related fields), but they use **different transport and framing**:

- USB/dongle: 90-byte HID feature report protocol
- BLE: vendor GATT request/notify protocol (`...1524` / `...1525`) with different packet structure

For clarity, documentation is now split:

- [USB Protocol](./USB_PROTOCOL.md)
- [BLE Protocol](./BLE_PROTOCOL.md)

