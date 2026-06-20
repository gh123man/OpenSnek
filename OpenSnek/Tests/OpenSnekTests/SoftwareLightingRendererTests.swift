import XCTest
import OpenSnekCore

final class SoftwareLightingRendererTests: XCTestCase {
    func testBasiliskV3FamilyLayoutMatchesValidatedCellMap() {
        let layout = SoftwareLightingFrameLayout.basiliskV3ProUSB
        XCTAssertEqual(layout.cellCount, 14)
        XCTAssertEqual(layout.cells.map(\.id), [
            "logo",
            "scroll_wheel",
            "underglow_left_front",
            "underglow_left_2",
            "underglow_left_3",
            "underglow_left_4",
            "underglow_left_rear",
            "underglow_right_rear",
            "underglow_right_2",
            "underglow_right_3",
            "underglow_right_middle",
            "underglow_right_front",
            "underglow_tail_1",
            "underglow_tail_2",
        ])
    }

    func testRendererProducesClampedFullFramesForEveryPreset() {
        for preset in SoftwareLightingPresetID.allCases {
            let frame = SoftwareLightingRenderer.render(
                request: SoftwareLightingEffectRequest(presetID: preset),
                layout: .basiliskV3ProUSB,
                elapsedTime: 1.25
            )
            XCTAssertEqual(frame.colors.count, 14)
            XCTAssertTrue(frame.colors.allSatisfy { color in
                (0...255).contains(color.r) &&
                    (0...255).contains(color.g) &&
                    (0...255).contains(color.b)
            })
        }
    }

    func testAnimatedPresetsRenderTailCellsInFourteenCellLayout() {
        for preset in SoftwareLightingPresetID.animatedPresets {
            let request = SoftwareLightingEffectRequest(presetID: preset)
            let frames = [
                SoftwareLightingRenderer.render(
                    request: request,
                    layout: .basiliskV3ProUSB,
                    elapsedTime: 0.0
                ),
                SoftwareLightingRenderer.render(
                    request: request,
                    layout: .basiliskV3ProUSB,
                    elapsedTime: 0.5
                ),
                SoftwareLightingRenderer.render(
                    request: request,
                    layout: .basiliskV3ProUSB,
                    elapsedTime: 2.75
                ),
            ]
            let tailSamples = frames.flatMap { [$0.colors[12], $0.colors[13]] }

            XCTAssertEqual(frames[0].colors.count, 14)
            XCTAssertTrue(
                tailSamples.contains { $0 != RGBPatch(r: 0, g: 0, b: 0) },
                "\(preset.rawValue) should render the newly addressed tail LEDs"
            )
        }
    }

    func testRenderingIsDeterministicForSamePresetAndTime() {
        let request = SoftwareLightingEffectRequest(presetID: .flame)
        let first = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 2.0
        )
        let second = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 2.0
        )
        XCTAssertEqual(first, second)
    }

    func testCustomPaletteChangesRenderedFrame() {
        let redFrame = SoftwareLightingRenderer.render(
            request: SoftwareLightingEffectRequest(
                presetID: .scrollingRainbow,
                palette: [RGBPatch(r: 255, g: 0, b: 0)]
            ),
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.25
        )
        let blueFrame = SoftwareLightingRenderer.render(
            request: SoftwareLightingEffectRequest(
                presetID: .scrollingRainbow,
                palette: [RGBPatch(r: 0, g: 0, b: 255)]
            ),
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.25
        )

        XCTAssertNotEqual(redFrame.colors, blueFrame.colors)
        XCTAssertTrue(redFrame.colors.allSatisfy { $0.r > 0 && $0.g == 0 && $0.b == 0 })
        XCTAssertTrue(blueFrame.colors.allSatisfy { $0.r == 0 && $0.g == 0 && $0.b > 0 })
    }

    func testIntensityScalesRenderedBrightness() {
        let fullFrame = SoftwareLightingRenderer.render(
            request: SoftwareLightingEffectRequest(
                presetID: .scrollingRainbow,
                intensity: 1.0,
                palette: [RGBPatch(r: 200, g: 100, b: 50)]
            ),
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0
        )
        let dimFrame = SoftwareLightingRenderer.render(
            request: SoftwareLightingEffectRequest(
                presetID: .scrollingRainbow,
                intensity: 0.25,
                palette: [RGBPatch(r: 200, g: 100, b: 50)]
            ),
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0
        )

        XCTAssertEqual(fullFrame.colors.first, RGBPatch(r: 190, g: 95, b: 48))
        XCTAssertEqual(dimFrame.colors.first, RGBPatch(r: 48, g: 24, b: 12))
    }

    func testPresetDefaultSpeeds() {
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .scrollingRainbow).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .flame).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .cometChase).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .nightRider).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .aurora).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .jellybeans).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .batteryMeter).speed, 0.0)
        XCTAssertEqual(SoftwareLightingPresetID.scrollingRainbow.renderSpeedMultiplier, 3.0)
    }

    func testFlameDefaultPaletteRemovesLightHighlight() {
        XCTAssertEqual(SoftwareLightingPresetID.flame.defaultPalette, [
            RGBPatch(r: 48, g: 0, b: 0),
            RGBPatch(r: 255, g: 48, b: 0),
            RGBPatch(r: 255, g: 176, b: 28),
        ])
    }

    func testJellybeansDefaultPaletteUsesSaturatedCandyColors() {
        XCTAssertEqual(SoftwareLightingPresetID.jellybeans.label, "Jellybeans")
        XCTAssertEqual(SoftwareLightingPresetID.jellybeans.defaultPalette, [
            RGBPatch(r: 255, g: 20, b: 96),
            RGBPatch(r: 255, g: 112, b: 0),
            RGBPatch(r: 255, g: 232, b: 0),
            RGBPatch(r: 46, g: 230, b: 54),
            RGBPatch(r: 0, g: 220, b: 255),
            RGBPatch(r: 0, g: 92, b: 255),
            RGBPatch(r: 144, g: 48, b: 255),
            RGBPatch(r: 255, g: 56, b: 228),
        ])
    }

    func testNightRiderDefaultPaletteUsesRedScanner() {
        XCTAssertEqual(SoftwareLightingPresetID.nightRider.label, "Night Rider")
        XCTAssertEqual(SoftwareLightingPresetID.nightRider.defaultPalette, [
            RGBPatch(r: 255, g: 0, b: 0),
        ])
        XCTAssertTrue(SoftwareLightingPresetID.nightRider.isAnimated)
        XCTAssertFalse(SoftwareLightingPresetID.nightRider.usesPaletteControls)
        XCTAssertTrue(SoftwareLightingPresetID.animatedPresets.contains(.nightRider))
    }

    func testBatteryMeterDefaultPaletteUsesThresholdColors() {
        XCTAssertEqual(SoftwareLightingPresetID.batteryMeter.label, "Battery Meter")
        XCTAssertEqual(SoftwareLightingPresetID.batteryMeter.defaultPalette, [
            RGBPatch(r: 255, g: 0, b: 0),
            RGBPatch(r: 255, g: 255, b: 0),
            RGBPatch(r: 255, g: 255, b: 255),
        ])
        XCTAssertFalse(SoftwareLightingPresetID.batteryMeter.isAnimated)
        XCTAssertFalse(SoftwareLightingPresetID.batteryMeter.usesPaletteControls)
        XCTAssertFalse(SoftwareLightingPresetID.batteryMeter.usesSpeedControl)
    }

    func testFlameRendersNonUniformFlickerAcrossCells() {
        let request = SoftwareLightingEffectRequest(presetID: .flame)
        let samples = stride(from: 0.0, through: 2.0, by: 0.1).map { elapsed in
            SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: elapsed
            )
        }

        XCTAssertGreaterThan(Set(samples[0].colors.dropFirst(2)).count, 1)
        XCTAssertNotEqual(samples[0].colors, samples[5].colors)
    }

    func testZeroSpeedRendersStaticFrame() {
        for preset in SoftwareLightingPresetID.allCases {
            let request = SoftwareLightingEffectRequest(presetID: preset, speed: 0)
            let first = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: 0.0
            )
            let second = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: 3.0
            )
            XCTAssertEqual(first.colors, second.colors, "\(preset.rawValue) should be static at zero speed")
        }
    }

    func testScrollingRainbowLoopsCleanlyForCustomPalettes() {
        let palettes = [
            [
                RGBPatch(r: 255, g: 0, b: 0),
                RGBPatch(r: 0, g: 255, b: 0),
            ],
            [
                RGBPatch(r: 255, g: 0, b: 0),
                RGBPatch(r: 0, g: 255, b: 0),
                RGBPatch(r: 0, g: 0, b: 255),
                RGBPatch(r: 255, g: 255, b: 0),
            ],
        ]
        let period = 1.0 / (0.18 * SoftwareLightingPresetID.scrollingRainbow.renderSpeedMultiplier)

        for palette in palettes {
            let request = SoftwareLightingEffectRequest(
                presetID: .scrollingRainbow,
                palette: palette
            )
            let first = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: 0.0
            )
            let looped = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: period
            )

            XCTAssertEqual(looped.colors, first.colors)
        }
    }

    func testScrollingRainbowUsesCyclicCellSpacing() {
        let request = SoftwareLightingEffectRequest(
            presetID: .scrollingRainbow,
            palette: [
                RGBPatch(r: 255, g: 0, b: 0),
                RGBPatch(r: 0, g: 255, b: 0),
                RGBPatch(r: 0, g: 0, b: 255),
            ]
        )
        let layout = SoftwareLightingFrameLayout.basiliskV3ProUSB
        let oneCellShiftTime = 1.0 / (
            Double(layout.cellCount) *
                0.18 *
                SoftwareLightingPresetID.scrollingRainbow.renderSpeedMultiplier
        )
        let first = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: 0.0
        )
        let shifted = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: oneCellShiftTime
        )

        XCTAssertNotEqual(first.colors.first, first.colors.last)
        XCTAssertEqual(shifted.colors[1], first.colors[0])
        XCTAssertEqual(shifted.colors[0], first.colors[layout.cellCount - 1])
    }

    func testJellybeansChangesOneRandomLEDPerTick() {
        let request = SoftwareLightingEffectRequest(presetID: .jellybeans)
        let first = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0
        )
        let second = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: (1.0 / 7.0) + 0.001
        )
        let changedIndices = zip(first.colors, second.colors).enumerated().compactMap { index, pair in
            pair.0 == pair.1 ? nil : index
        }

        let renderedDefaultPalette = Set(SoftwareLightingPresetID.jellybeans.defaultPalette.map { color in
            RGBPatch(
                r: Int(round(Double(color.r) * 0.95)),
                g: Int(round(Double(color.g) * 0.95)),
                b: Int(round(Double(color.b) * 0.95))
            )
        })

        XCTAssertGreaterThan(Set(first.colors).count, 1)
        XCTAssertEqual(changedIndices.count, 1)
        if let changedIndex = changedIndices.first {
            XCTAssertTrue(renderedDefaultPalette.contains(second.colors[changedIndex]))
        }
    }

    func testNightRiderSweepsUnderglowAndPulsesLogoAndScrollWheel() {
        let request = SoftwareLightingEffectRequest(presetID: .nightRider)
        let layout = SoftwareLightingFrameLayout.basiliskV3ProUSB
        let start = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: 0.0
        )
        let rear = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: 11.0 / 4.0
        )
        let returned = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: 22.0 / 4.0
        )
        let pulseHigh = SoftwareLightingRenderer.render(
            request: request,
            layout: layout,
            elapsedTime: .pi / 1.1
        )

        XCTAssertEqual(brightestStripIndex(in: start), 2)
        XCTAssertEqual(brightestStripIndex(in: rear), 13)
        XCTAssertEqual(brightestStripIndex(in: returned), 2)
        XCTAssertGreaterThan(pulseHigh.colors[0].r, start.colors[0].r)
        XCTAssertGreaterThan(pulseHigh.colors[1].r, start.colors[1].r)
        XCTAssertEqual(pulseHigh.colors[0], pulseHigh.colors[1])
        XCTAssertEqual(start.colors[0].g, 0)
        XCTAssertEqual(start.colors[0].b, 0)
        XCTAssertEqual(start.colors[1].g, 0)
        XCTAssertEqual(start.colors[1].b, 0)
    }

    func testBatteryMeterRendersUnknownBatteryWithWhiteLogoAndScrollWheel() {
        let frame = SoftwareLightingRenderer.render(
            request: SoftwareLightingEffectRequest(presetID: .batteryMeter),
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0
        )

        XCTAssertEqual(frame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(frame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(Array(frame.colors.dropFirst(2)), Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 12))
    }

    func testBatteryMeterUsesUnderglowProgressBarAndThresholdColors() {
        let request = SoftwareLightingEffectRequest(presetID: .batteryMeter)
        let emptyFrame = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 0
        )
        let redFrame = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 14
        )
        let yellowFrame = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 15
        )
        let whiteFrame = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 74
        )
        let halfFrame = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 50
        )

        XCTAssertEqual(emptyFrame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(emptyFrame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(
            Array(emptyFrame.colors.dropFirst(2)),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 12)
        )

        XCTAssertEqual(redFrame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(redFrame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(redFrame.colors[2], RGBPatch(r: 255, g: 0, b: 0))
        XCTAssertEqual(redFrame.colors[3], RGBPatch(r: 173, g: 0, b: 0))
        XCTAssertEqual(
            Array(redFrame.colors.dropFirst(4)),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 10)
        )

        XCTAssertEqual(yellowFrame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(yellowFrame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(yellowFrame.colors[2], RGBPatch(r: 255, g: 255, b: 0))
        XCTAssertEqual(yellowFrame.colors[3], RGBPatch(r: 204, g: 204, b: 0))
        XCTAssertEqual(
            Array(yellowFrame.colors.dropFirst(4)),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 10)
        )

        XCTAssertEqual(whiteFrame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(whiteFrame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(
            Array(whiteFrame.colors[2...9]),
            Array(repeating: RGBPatch(r: 255, g: 255, b: 255), count: 8)
        )
        XCTAssertEqual(whiteFrame.colors[10], RGBPatch(r: 224, g: 224, b: 224))
        XCTAssertEqual(
            Array(whiteFrame.colors[11...13]),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 3)
        )
        XCTAssertFalse(whiteFrame.colors.contains(RGBPatch(r: 255, g: 255, b: 0)))

        XCTAssertEqual(halfFrame.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(halfFrame.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(
            Array(halfFrame.colors[2...7]),
            Array(repeating: RGBPatch(r: 255, g: 255, b: 255), count: 6)
        )
        XCTAssertEqual(
            Array(halfFrame.colors[8...13]),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 6)
        )
        XCTAssertFalse(halfFrame.colors.contains(RGBPatch(r: 255, g: 255, b: 0)))
    }

    func testBatteryMeterFadesBoundaryCellByBatterySubPercentage() {
        let request = SoftwareLightingEffectRequest(presetID: .batteryMeter)

        let justAboveHalf = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 51
        )
        let nearFull = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 99
        )

        XCTAssertEqual(
            Array(justAboveHalf.colors[2...7]),
            Array(repeating: RGBPatch(r: 255, g: 255, b: 255), count: 6)
        )
        XCTAssertEqual(justAboveHalf.colors[8], RGBPatch(r: 31, g: 31, b: 31))
        XCTAssertEqual(
            Array(justAboveHalf.colors[9...13]),
            Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 5)
        )

        XCTAssertEqual(
            Array(nearFull.colors[2...12]),
            Array(repeating: RGBPatch(r: 255, g: 255, b: 255), count: 11)
        )
        XCTAssertEqual(nearFull.colors[13], RGBPatch(r: 224, g: 224, b: 224))
    }

    func testBatteryMeterIsStableOverTime() {
        let request = SoftwareLightingEffectRequest(presetID: .batteryMeter)
        let first = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 0.0,
            batteryPercent: 74
        )
        let second = SoftwareLightingRenderer.render(
            request: request,
            layout: .basiliskV3ProUSB,
            elapsedTime: 4.0,
            batteryPercent: 74
        )

        XCTAssertEqual(first.colors, second.colors)
    }

    func testAnimatedPresetsMoveOverTime() {
        for preset in SoftwareLightingPresetID.allCases where preset.isAnimated {
            let request = SoftwareLightingEffectRequest(presetID: preset)
            let first = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: 0.0
            )
            let second = SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: 0.75
            )
            XCTAssertNotEqual(first.colors, second.colors, "\(preset.rawValue) should change over time")
        }
    }

    private func brightestStripIndex(in frame: USBLightingFramePatch) -> Int? {
        (2..<frame.colors.count).max { lhs, rhs in
            frame.colors[lhs].r < frame.colors[rhs].r
        }
    }
}
