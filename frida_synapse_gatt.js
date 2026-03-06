/**
 * Frida script: attach to Razer Synapse and log BLE GATT-related activity.
 *
 * Run (with Synapse already open):
 *   frida -l frida_synapse_gatt.js -n "RazerAppEngine"
 * Or by PID:
 *   frida -l frida_synapse_gatt.js -p <PID>
 *
 * Goal: capture GattCharacteristic.WriteValueAsync payloads (char UUID + hex).
 * WinRT APIs may not be direct exports; we enumerate modules and hook what we can.
 */

"use strict";

function sendRecord(rec) {
  rec.time = rec.time || (Date.now() / 1000);
  rec.pid = Process.id;
  if (typeof send === "function") send({ type: "gatt_record", payload: rec });
}

console.log("[*] Frida script loaded. Target: Razer Synapse BLE GATT.");
console.log("[*] Attached to PID " + Process.id);
console.log("[*] Enumerating loaded modules (Bluetooth-related)...\n");

var bluetoothModules = [];
Process.enumerateModules().forEach(function (m) {
  var name = m.name.toLowerCase();
  if (name.indexOf("bluetooth") !== -1 || name.indexOf("ble") !== -1 || name.indexOf("gatt") !== -1 || name.indexOf("radio") !== -1) {
    bluetoothModules.push(m);
    console.log("  " + m.name + " @ " + m.base);
  }
});

if (bluetoothModules.length === 0) {
  console.log("  (none found in process - Synapse may use system BLE stack)");
} else {
  var wdb = Process.getModuleByName("Windows.Devices.Bluetooth.dll");
  if (wdb && typeof wdb.enumerateExports === "function") {
    var gattExports = [];
    try {
      wdb.enumerateExports().forEach(function (exp) {
        var n = (exp.name || "").toLowerCase();
        if (n.indexOf("write") !== -1 || n.indexOf("gatt") !== -1 || n.indexOf("characteristic") !== -1) gattExports.push(exp.name + " @ " + exp.address);
      });
      if (gattExports.length > 0) {
        console.log("\n  Windows.Devices.Bluetooth.dll exports (Write/Gatt/Characteristic):");
        gattExports.slice(0, 30).forEach(function (s) { console.log("    " + s); });
        if (gattExports.length > 30) console.log("    ... and " + (gattExports.length - 30) + " more");
      }
    } catch (e) {}
  }
}

console.log("\n[*] Hooking kernel32 CreateFileW to catch BLE device opens (optional)...");

try {
  var k32 = Process.getModuleByName("kernel32.dll");
  var kbase = Process.getModuleByName("kernelbase.dll");
  var createFileW = (k32 && k32.findExportByName("CreateFileW")) || (kbase && kbase.findExportByName("CreateFileW"));
  if (createFileW && typeof Interceptor !== "undefined" && typeof Interceptor.attach === "function") {
    var addr = (typeof ptr === "function") ? ptr(createFileW) : createFileW;
    Interceptor.attach(addr, {
      onEnter: function (args) {
        try {
          var pathPtr = args[0];
          if (pathPtr && !pathPtr.isNull()) {
            var path = Memory.readUtf16String(pathPtr);
            if (path && (path.indexOf("BTH") !== -1 || path.indexOf("bluetooth") !== -1 || path.indexOf("BLE") !== -1)) {
              this.path = path;
            }
          }
        } catch (e) {}
      },
      onLeave: function (retval) {
        if (this.path) {
          console.log("[CreateFileW BLE] " + this.path + " -> handle " + retval);
          sendRecord({ op: "open", path: this.path, handle: retval.toString() });
        }
      },
    });
    console.log("  CreateFileW hook installed.");
  } else {
    console.log("  CreateFileW not found or Interceptor unavailable.");
  }
} catch (e) {
  console.log("  Hook failed: " + e);
}

console.log("\n[*] Looking for Win32 BLE GATT API (BluetoothGATTSetCharacteristicValue)...");

try {
  var setCharAddr = null;
  var dllName = null;
  Process.enumerateModules().forEach(function (m) {
    if (setCharAddr) return;
    try {
      var exp = m.findExportByName("BluetoothGATTSetCharacteristicValue");
      if (exp) {
        setCharAddr = exp;
        dllName = m.name;
      }
    } catch (e) {}
  });

  if (setCharAddr && dllName) {
    console.log("  Found in " + dllName + " @ " + setCharAddr);
    Interceptor.attach(setCharAddr, {
      onEnter: function (args) {
        this.hDevice = args[0];
        this.pChar = args[1];
        this.pValue = args[2];
        try {
          if (this.pChar && !this.pChar.isNull()) {
            this.charServiceHandle = this.pChar.readU16();
            var isShort = this.pChar.add(2).readU8();
            var uuidLen = isShort ? 2 : 16;
            if (isShort) {
              this.charUuidHex = this.pChar.add(3).readU16().toString(16);
            } else {
              var u = this.pChar.add(3).readByteArray(16);
              if (u) this.charUuidHex = Array.from(new Uint8Array(u)).map(function (b) { return ("0" + (b & 0xff).toString(16)).slice(-2); }).join("");
            }
            var handleOff = 2 + 1 + uuidLen;
            this.charAttrHandle = this.pChar.add(handleOff).readU16();
            this.charValueHandle = this.pChar.add(handleOff + 2).readU16();
          }
          if (this.pValue && !this.pValue.isNull()) {
            var dataSize = this.pValue.readU32();
            this.dataSize = dataSize;
            if (dataSize > 0 && dataSize <= 512) {
              var dataPtr = this.pValue.add(8);
              var maybePtr = dataPtr.readPointer();
              if (maybePtr && !maybePtr.isNull()) this.dataPtr = maybePtr;
              else this.dataPtr = dataPtr;
            }
          }
        } catch (e) {
          this.parseError = e.toString();
        }
      },
      onLeave: function (retval) {
        var line = "[GATT WRITE]";
        var payloadHex = "";
        if (this.charUuidHex !== undefined) line += " char_uuid=" + this.charUuidHex;
        if (this.charValueHandle !== undefined) line += " valueHandle=" + this.charValueHandle;
        if (this.charAttrHandle !== undefined) line += " attrHandle=" + this.charAttrHandle;
        if (this.dataSize !== undefined && this.dataPtr) {
          try {
            var buf = this.dataPtr.readByteArray(this.dataSize);
            if (buf) {
              payloadHex = Array.from(new Uint8Array(buf)).map(function (b) { return ("0" + (b & 0xff).toString(16)).slice(-2); }).join("");
              line += " size=" + this.dataSize + " payload_hex=" + payloadHex;
            }
          } catch (e) {}
        }
        if (this.parseError) line += " parseErr=" + this.parseError;
        if (this.charValueHandle !== undefined || this.dataSize !== undefined) {
          console.log(line);
          sendRecord({
            op: "write",
            service_uuid: "",
            char_uuid: this.charUuidHex || "",
            handle: this.charValueHandle,
            write_mode: "with_response",
            value_hex: payloadHex
          });
        }
      },
    });
    console.log("  BluetoothGATTSetCharacteristicValue hook installed.");
  } else {
    console.log("  BluetoothGATTSetCharacteristicValue not found (WinRT-only path?).");
  }
} catch (e) {
  console.log("  BLE GATT hook failed: " + e);
}

console.log("\n[*] Hooking DeviceIoControl to catch BLE-related IOCTLs (fallback for WinRT path)...");

try {
  var k32 = Process.getModuleByName("kernel32.dll");
  var kbase = Process.getModuleByName("kernelbase.dll");
  var devIoCtrl = (k32 && k32.findExportByName("DeviceIoControl")) || (kbase && kbase.findExportByName("DeviceIoControl"));
  if (devIoCtrl) {
    Interceptor.attach(devIoCtrl, {
      onEnter: function (args) {
        this.hDevice = args[0];
        this.ioctl = args[1].toInt32 ? args[1].toInt32() : args[1].toU32();
        this.lpIn = args[2];
        this.nIn = args[3].toInt32();
        this.lpOut = args[4];
        this.nOut = args[5].toInt32();
      },
      onLeave: function (retval) {
        if (this.nIn > 0 && this.nIn <= 512 && this.lpIn && !this.lpIn.isNull()) {
          try {
            var len = Math.min(this.nIn, 256);
            var buf = this.lpIn.readByteArray(len);
            if (buf) {
              var hex = Array.from(new Uint8Array(buf)).map(function (b) { return ("0" + (b & 0xff).toString(16)).slice(-2); }).join("");
              var hexFull = (this.nIn <= 256) ? hex : hex + "...";
              console.log("[DeviceIoControl] ioctl=0x" + (this.ioctl >>> 0).toString(16) + " inLen=" + this.nIn + " inHex=" + hexFull);
              sendRecord({
                op: "write",
                service_uuid: "",
                char_uuid: "",
                handle: "",
                write_mode: "ioctl",
                ioctl: "0x" + (this.ioctl >>> 0).toString(16),
                value_hex: (this.nIn <= 256) ? hex : hex
              });
            }
          } catch (e) {}
        }
      },
    });
    console.log("  DeviceIoControl hook installed (logging calls with 4-256 byte input).");
  }
} catch (e) {
  console.log("  DeviceIoControl hook failed: " + e);
}

console.log("\n[*] Script ready. Change a setting in Synapse (e.g. DPI 800->1600) and watch for [GATT WRITE], [DeviceIoControl], or [CreateFileW BLE] logs.\n");
