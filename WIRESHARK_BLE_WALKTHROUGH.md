# Wireshark BLE capture walkthrough (Windows)

Use Wireshark to capture Bluetooth LE traffic when you change a setting (e.g. DPI) in Razer Synapse. Goal: see GATT write packets and the payload.

---

## Step 1: Install Wireshark and Npcap

1. **Npcap** (required for capture on Windows):
   - Go to **https://npcap.com/#download**
   - Download the installer and run it.
   - Use default options; leave **“WinPcap API-compatible mode”** checked if asked.

2. **Wireshark**:
   - Go to **https://www.wireshark.org/download.html**
   - Download the Windows installer and run it.
   - When it asks, choose to use **Npcap** for capturing.
   - Reboot if the installer suggests it (so Npcap is loaded).

---

## Step 2: Run Wireshark as Administrator

- Right‑click **Wireshark** → **Run as administrator**.  
  (Needed to see all capture interfaces and to capture on Bluetooth/USB.)

---

## Step 3: See which interfaces you have

1. Start Wireshark (as Admin).
2. Look at the **capture interface list** (main window, or **Capture → Options**).
3. Check for any of:
   - **Bluetooth** / **BTH** / **Bluetooth LE** (if Windows exposes them – many PCs do not).
   - **USBPcap1**, **USBPcap2**, … (if USBPcap is installed; see Step 3b).
   - **Local area connection** / **Wi‑Fi** (we don’t use these for BLE).

**If you see a Bluetooth-related interface:** use it and go to Step 4.

**If you only see Ethernet/Wi‑Fi and no Bluetooth:**  
Windows often does not expose a dedicated “Bluetooth” interface to Wireshark. In that case you have two options:

- **Option A:** Install **USBPcap** and capture the **USB device** that is your Bluetooth adapter (Step 3b). That gives you HCI over USB; Wireshark can decode it as Bluetooth.
- **Option B:** Use an external BLE sniffer (e.g. **nRF Sniffer** with an nRF52840 dongle) and capture in Wireshark – see [APPROACH_BT_ALTERNATIVES.md](APPROACH_BT_ALTERNATIVES.md).

---

## Step 3b (optional): USBPcap to capture the Bluetooth USB adapter

If your Bluetooth is built-in or you have a **USB Bluetooth dongle**, you can capture its USB traffic (HCI):

1. **USBPcap**:
   - **https://desowin.org/usbpcap/**  
   - Download and install. Restart if asked.
2. In Wireshark (as Admin), open **Capture → Options**.
3. You should see **USBPcap1**, **USBPcap2**, etc. Each corresponds to a USB controller or device.
4. To find which one is the Bluetooth adapter:
   - In **Device Manager**, under **Bluetooth** or **Universal Serial Bus devices**, note the name (e.g. “Intel Wireless Bluetooth”).
   - In Wireshark, start a short capture on **USBPcap1**, then **USBPcap2**, etc., and see which one gets traffic when you move the mouse or change DPI. The one that shows **bthci_*** or **bluetooth** packets when you use the mouse is the right one.
5. Use that **USBPcap** interface for the capture in Step 4.

---

## Step 4: Start the capture

1. **Prepare:**
   - Mouse paired over **Bluetooth** (not USB cable).
   - **Razer Synapse** open and able to change settings (e.g. DPI).

2. In Wireshark, select the **Bluetooth** or **USBPcap** interface (the one you identified).
3. Click the **blue shark fin** (Start capturing) or double‑click the interface.
4. Let it run for a few seconds with no changes (baseline).
5. In Synapse, change **one** setting – e.g. **DPI from 800 to 1600** – **once**.
6. Wait 5–10 seconds.
7. Click the **red square** (Stop capturing).

---

## Step 5: Filter for BLE / GATT traffic

In the filter bar at the top, try (one at a time):

- **`btatt`** – ATT protocol (GATT is built on ATT). You want **Write Request** / **Write Command** and optionally **Handle Value Notification**.
- **`bthci_acl`** – ACL data (often carries ATT).
- **`bluetooth`** – all Bluetooth.

If you captured over **USBPcap**, first apply **`usb`** and see if Wireshark shows **Bluetooth HCI** as the protocol; if so, you may need to use **`bthci_*`** or **`btatt`** once the decode is correct.

**What to look for:**

- **ATT Write Request** or **Write Command** – these are GATT writes.
- In the packet details, expand **Bluetooth ATT** (or **ATT**):
  - **Opcode** (e.g. Write Request = 0x12).
  - **Handle** (characteristic handle).
  - **Value** – the payload in hex; this is the config data (e.g. DPI).

If the connection uses **encryption** (LE Secure Connections), the **Value** field may be encrypted and you’ll only see handle/length/timing, not the actual bytes.

---

## Step 6: Find the DPI change packet

1. Scroll through the (filtered) packets around the time you changed DPI.
2. Look for a **Write Request** (or **Write Command**) that appears **once** or a few times right after you clicked “apply” in Synapse.
3. Click that packet and in the details panel expand:
   - **Bluetooth ATT** → **Attribute Protocol** → **Value** (or similar).
4. Copy the **Value** (hex). That’s your candidate DPI write payload.  
   Also note:
   - **Handle** (e.g. 0x0025).
   - **Opcode** (0x12 = Write Request, 0x52 = Write Command).

---

## Step 7: Save and export

1. **Save the capture:** **File → Save As** and save as e.g. `dpi_change.pcapng`.
2. **For the runbook:** Note in `artifacts/DELIVERABLES_TEMPLATE.md` (or a text file):
   - Handle (hex).
   - Opcode (Write Request vs Write Command).
   - Value (hex) of the packet that coincided with the DPI change.

You can then try replaying that value with `ble_write_runner.py` (on a machine where you can open the GATT characteristic) using the same handle or the characteristic UUID that corresponds to that handle.

---

## Troubleshooting

| Problem | What to try |
|--------|-------------|
| No Bluetooth interface in Wireshark | Normal on many Windows setups. Use USBPcap (Step 3b) for the BT USB device, or an nRF Sniffer / Ubertooth. |
| USBPcap shows no traffic when changing DPI | Confirm you selected the correct USBPcap interface (the one for the BT adapter). Try moving the mouse; the interface that gets traffic is the right one. |
| Only HCI, no ATT / btatt | HCI is correct; Wireshark decodes ATT inside ACL. Apply filter **btatt**; if still empty, the stack may not be exposing ATT in a decodable way – consider nRF Sniffer. |
| Value field is encrypted / unreadable | Link is encrypted (LE Secure Connections). You can still note handle, opcode, and length for correlation; payload recovery would need another approach (e.g. trial writes from macOS). |
| Too much traffic | Restart capture, then do **only** one action (e.g. one DPI change) and stop quickly. Use **btatt** and time to narrow it down. |

---

## Quick reference

1. Install Npcap + Wireshark (and optionally USBPcap).
2. Run Wireshark **as Administrator**.
3. Select **Bluetooth** or **USBPcap** (for BT adapter).
4. Start capture → change DPI once in Synapse → stop.
5. Filter **btatt** → find **Write Request** / **Write Command** near that time.
6. Note **Handle**, **Opcode**, **Value (hex)** and save the pcap.
