/// Filters profile content and backend requests to the controls a USB device supports.
public extension DevicePatch {
    func supportedUSBControls(for device: MouseDevice) -> DevicePatch {
        guard device.transport == .usb, let profile = DeviceProfiles.resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport) else { return self }

        var supported = self
        if !profile.supportsDPIControls {
            supported.dpiStages = nil
            supported.dpiStagePairs = nil
            supported.activeStage = nil
        }
        if !profile.supportsPollRateControls { supported.pollRate = nil }
        if !profile.supportsPowerManagementControls {
            supported.sleepTimeout = nil
            supported.lowBatteryThresholdRaw = nil
        }
        if !profile.supportsButtonRemapControls {
            supported.buttonBinding = nil
            supported.usbButtonProfileAction = nil
        }
        return supported
    }

    /// Clears onboard lighting writes so running software lighting frames are not overwritten.
    var withoutOnboardLightingWrites: DevicePatch {
        var copy = self
        copy.ledRGB = nil
        copy.lightingEffect = nil
        copy.usbLightingZoneLEDIDs = nil
        return copy
    }
}
