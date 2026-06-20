import XCTest
import OpenSnekCore
@testable import OpenSnek

final class LightingSummaryPresentationTests: XCTestCase {
    func testBatteryMeterSummaryUsesBatteryIconInsteadOfPaletteSwatches() {
        let presentation = LightingSummaryPresentation.make(
            supportsSoftwareLightingEffects: true,
            softwareLightingStatus: SoftwareLightingEngineStatus(
                deviceID: "lighting-summary-device",
                state: .running,
                request: SoftwareLightingEffectRequest(
                    presetID: .batteryMeter,
                    palette: SoftwareLightingPresetID.flame.defaultPalette
                )
            ),
            editableSoftwareLightingPreset: .flame,
            editableSoftwareLightingPalette: SoftwareLightingPresetID.flame.defaultPalette.map {
                RGBColor(r: $0.r, g: $0.g, b: $0.b)
            },
            onboardEffectLabel: "Static",
            onboardColors: [RGBColor(r: 255, g: 0, b: 0)],
            fallbackColor: RGBColor(r: 0, g: 255, b: 0),
            batteryState: makeLightingSummaryState(batteryPercent: 74)
        )

        XCTAssertEqual(presentation.title, "Battery Meter")
        XCTAssertEqual(presentation.swatches, [])
        XCTAssertEqual(presentation.batteryIcon?.symbolName, "battery.75percent")
        XCTAssertEqual(presentation.batteryIcon?.variableValue, 0.75)
    }

    func testRunningSoftwareLightingSummaryUsesRunningRequestPalette() {
        let presentation = LightingSummaryPresentation.make(
            supportsSoftwareLightingEffects: true,
            softwareLightingStatus: SoftwareLightingEngineStatus(
                deviceID: "lighting-summary-device",
                state: .running,
                request: SoftwareLightingEffectRequest(
                    presetID: .aurora,
                    palette: [RGBPatch(r: 1, g: 2, b: 3)]
                )
            ),
            editableSoftwareLightingPreset: .flame,
            editableSoftwareLightingPalette: SoftwareLightingPresetID.flame.defaultPalette.map {
                RGBColor(r: $0.r, g: $0.g, b: $0.b)
            },
            onboardEffectLabel: "Static",
            onboardColors: [RGBColor(r: 255, g: 0, b: 0)],
            fallbackColor: RGBColor(r: 0, g: 255, b: 0),
            batteryState: makeLightingSummaryState(batteryPercent: 74)
        )

        XCTAssertEqual(presentation.title, "Aurora")
        XCTAssertEqual(presentation.swatches, [RGBColor(r: 1, g: 2, b: 3)])
        XCTAssertNil(presentation.batteryIcon)
    }
}

private func makeLightingSummaryState(batteryPercent: Int) -> MouseState {
    MouseState(
        device: DeviceSummary(
            id: "lighting-summary-device",
            product_name: "Basilisk V3 Pro",
            serial: "LIGHTING-SUMMARY",
            transport: .usb,
            firmware: "1.0.0"
        ),
        connection: "USB",
        battery_percent: batteryPercent,
        charging: false,
        dpi: DpiPair(x: 800, y: 800),
        dpi_stages: DpiStages(active_stage: 0, values: [800, 1600, 3200]),
        poll_rate: 1000,
        device_mode: nil,
        low_battery_threshold_raw: nil,
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: true,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )
}
