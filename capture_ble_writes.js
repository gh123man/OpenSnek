/*
 * Frida script to hook Windows Runtime Bluetooth LE GATT write operations.
 * From RUNBOOK_WINDOWS_BT_RE.md Method 2.
 *
 * Target APIs:
 *   Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic
 *     - WriteValueAsync(IBuffer)
 *     - WriteValueWithResultAsync(IBuffer)
 *     - WriteValueWithResultAndOptionAsync(IBuffer, GattWriteOption)
 *
 * Also hooks: DeviceIoControl (BLE IOCTLs), BluetoothGATT* (bluetoothapis.dll), HidD_* (hid.dll).
 */

'use strict';

function log(msg) {
    var ts = new Date().toISOString();
    send({ type: 'log', ts: ts, msg: msg });
    console.log('[' + ts + '] ' + msg);
}

function bufferToHex(bufPtr, length) {
    if (!bufPtr || length <= 0) return '';
    try {
        var bytes = [];
        for (var i = 0; i < length; i++) {
            bytes.push(('0' + bufPtr.add(i).readU8().toString(16)).slice(-2));
        }
        return bytes.join(' ');
    } catch (e) {
        return '<read error: ' + e + '>';
    }
}

var kernel32 = Module.findBaseAddress('kernel32.dll');
var deviceIoControl = Module.findExportByName('kernel32.dll', 'DeviceIoControl');

if (deviceIoControl) {
    Interceptor.attach(deviceIoControl, {
        onEnter: function(args) {
            var ioctl = args[1].toInt32() >>> 0;
            var inSize = args[3].toInt32();
            if ((ioctl & 0xFF0000) === 0x410000 && inSize > 0) {
                this.ioctl = ioctl;
                this.inBuf = args[2];
                this.inSize = inSize;
            }
        },
        onLeave: function(retval) {
            if (this.ioctl) {
                var hex = bufferToHex(this.inBuf, Math.min(this.inSize, 128));
                log('DeviceIoControl IOCTL=0x' + this.ioctl.toString(16) +
                    ' size=' + this.inSize + ' data=[' + hex + ']');
            }
        }
    });
    log('Hooked DeviceIoControl for BLE IOCTLs');
}

var btApis = Module.findBaseAddress('bluetoothapis.dll');
if (btApis) {
    var setCharValue = Module.findExportByName('bluetoothapis.dll',
        'BluetoothGATTSetCharacteristicValue');
    if (setCharValue) {
        Interceptor.attach(setCharValue, {
            onEnter: function(args) {
                var charPtr = args[1];
                var valuePtr = args[2];
                log('BluetoothGATTSetCharacteristicValue called');
                if (valuePtr) {
                    try {
                        var dataSize = valuePtr.readU32();
                        var dataHex = bufferToHex(valuePtr.add(4), Math.min(dataSize, 128));
                        log('  GATT Write: size=' + dataSize + ' payload=[' + dataHex + ']');
                    } catch(e) {
                        log('  GATT Write: parse error: ' + e);
                    }
                }
                if (charPtr) {
                    try {
                        var attrHandle = charPtr.add(0).readU16();
                        var charUuidType = charPtr.add(2).readU16();
                        log('  Char handle=0x' + attrHandle.toString(16) + ' uuidType=' + charUuidType);
                        var structHex = bufferToHex(charPtr, 48);
                        log('  Char struct=[' + structHex + ']');
                    } catch(e) {
                        log('  Char struct parse error: ' + e);
                    }
                }
            },
            onLeave: function(retval) {
                log('  GATT Write returned: ' + retval);
            }
        });
        log('Hooked BluetoothGATTSetCharacteristicValue');
    }

    var getCharValue = Module.findExportByName('bluetoothapis.dll',
        'BluetoothGATTGetCharacteristicValue');
    if (getCharValue) {
        Interceptor.attach(getCharValue, {
            onEnter: function(args) {
                this.valuePtr = args[2];
                this.sizePtr = args[3];
                log('BluetoothGATTGetCharacteristicValue called');
            },
            onLeave: function(retval) {
                if (retval.toInt32() === 0 && this.valuePtr) {
                    try {
                        var dataSize = this.valuePtr.readU32();
                        var dataHex = bufferToHex(this.valuePtr.add(4), Math.min(dataSize, 128));
                        log('  GATT Read result: size=' + dataSize + ' data=[' + dataHex + ']');
                    } catch(e) {}
                }
            }
        });
        log('Hooked BluetoothGATTGetCharacteristicValue');
    }

    var regEvent = Module.findExportByName('bluetoothapis.dll',
        'BluetoothGATTRegisterEvent');
    if (regEvent) {
        Interceptor.attach(regEvent, {
            onEnter: function(args) {
                log('BluetoothGATTRegisterEvent called (notification subscribe)');
                try {
                    var structHex = bufferToHex(args[1], 48);
                    log('  EventParam struct=[' + structHex + ']');
                } catch(e) {}
            }
        });
        log('Hooked BluetoothGATTRegisterEvent');
    }
} else {
    log('WARNING: bluetoothapis.dll not loaded in this process');
}

var hid = Module.findBaseAddress('hid.dll');
if (hid) {
    var hidSetFeature = Module.findExportByName('hid.dll', 'HidD_SetFeature');
    if (hidSetFeature) {
        Interceptor.attach(hidSetFeature, {
            onEnter: function(args) {
                var bufSize = args[2].toInt32();
                var hex = bufferToHex(args[1], Math.min(bufSize, 128));
                log('HidD_SetFeature size=' + bufSize + ' data=[' + hex + ']');
            },
            onLeave: function(retval) {
                log('  HidD_SetFeature returned: ' + retval);
            }
        });
        log('Hooked HidD_SetFeature');
    }

    var hidSetOutput = Module.findExportByName('hid.dll', 'HidD_SetOutputReport');
    if (hidSetOutput) {
        Interceptor.attach(hidSetOutput, {
            onEnter: function(args) {
                var bufSize = args[2].toInt32();
                var hex = bufferToHex(args[1], Math.min(bufSize, 128));
                log('HidD_SetOutputReport size=' + bufSize + ' data=[' + hex + ']');
            },
            onLeave: function(retval) {
                log('  HidD_SetOutputReport returned: ' + retval);
            }
        });
        log('Hooked HidD_SetOutputReport');
    }

    var hidGetFeature = Module.findExportByName('hid.dll', 'HidD_GetFeature');
    if (hidGetFeature) {
        Interceptor.attach(hidGetFeature, {
            onEnter: function(args) {
                this.buf = args[1];
                this.size = args[2].toInt32();
            },
            onLeave: function(retval) {
                if (retval.toInt32() !== 0) {
                    var hex = bufferToHex(this.buf, Math.min(this.size, 128));
                    log('HidD_GetFeature size=' + this.size + ' data=[' + hex + ']');
                }
            }
        });
        log('Hooked HidD_GetFeature');
    }
} else {
    log('WARNING: hid.dll not loaded in this process');
}

log('=== Frida BLE capture script loaded ===');
log('Waiting for GATT writes and HID operations...');
