import XCTest
import OpenSnekCore
@testable import OpenSnek

final class LightingCardTabPreferenceTests: XCTestCase {
    func testPreferredTabUsesAdvancedWhenApplyOnConnectIsEnabled() {
        XCTAssertEqual(
            LightingCardTab.preferred(
                supportsSoftwareLightingEffects: true,
                applyOnConnect: true,
                softwareLightingStatus: nil
            ),
            .advanced
        )
    }

    func testPreferredTabUsesAdvancedWhenSoftwareLightingIsRunning() {
        XCTAssertEqual(
            LightingCardTab.preferred(
                supportsSoftwareLightingEffects: true,
                applyOnConnect: false,
                softwareLightingStatus: SoftwareLightingEngineStatus(
                    deviceID: "lighting-card-running",
                    state: .running,
                    request: SoftwareLightingEffectRequest(presetID: .aurora)
                )
            ),
            .advanced
        )
    }

    func testPreferredTabUsesOnboardWhenSoftwareLightingIsInactive() {
        XCTAssertEqual(
            LightingCardTab.preferred(
                supportsSoftwareLightingEffects: true,
                applyOnConnect: false,
                softwareLightingStatus: nil
            ),
            .onboard
        )
    }

    func testPreferredTabUsesOnboardWhenSoftwareLightingIsUnsupported() {
        XCTAssertEqual(
            LightingCardTab.preferred(
                supportsSoftwareLightingEffects: false,
                applyOnConnect: true,
                softwareLightingStatus: SoftwareLightingEngineStatus(
                    deviceID: "lighting-card-unsupported",
                    state: .running,
                    request: SoftwareLightingEffectRequest(presetID: .aurora)
                )
            ),
            .onboard
        )
    }
}
