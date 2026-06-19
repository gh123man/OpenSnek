import XCTest
import OpenSnekCore

final class SoftwareLightingRendererTests: XCTestCase {
    func testBasiliskV3ProLayoutMatchesValidatedCellMap() {
        let layout = SoftwareLightingFrameLayout.basiliskV3ProUSB
        XCTAssertEqual(layout.cellCount, 12)
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
        ])
    }

    func testRendererProducesClampedFullFramesForEveryPreset() {
        for preset in SoftwareLightingPresetID.allCases {
            let frame = SoftwareLightingRenderer.render(
                request: SoftwareLightingEffectRequest(presetID: preset),
                layout: .basiliskV3ProUSB,
                elapsedTime: 1.25
            )
            XCTAssertEqual(frame.colors.count, 12)
            XCTAssertTrue(frame.colors.allSatisfy { color in
                (0...255).contains(color.r) &&
                    (0...255).contains(color.g) &&
                    (0...255).contains(color.b)
            })
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

    func testPresetDefaultSpeeds() {
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .scrollingRainbow).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .flame).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .cometChase).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .aurora).speed, 1.0)
        XCTAssertEqual(SoftwareLightingEffectRequest(presetID: .jellybeans).speed, 1.0)
        XCTAssertEqual(SoftwareLightingPresetID.scrollingRainbow.renderSpeedMultiplier, 3.0)
    }

    func testFlameDefaultPaletteRemovesLightHighlight() {
        XCTAssertEqual(SoftwareLightingPresetID.flame.defaultPalette, [
            RGBPatch(r: 48, g: 0, b: 0),
            RGBPatch(r: 255, g: 48, b: 0),
            RGBPatch(r: 255, g: 176, b: 28),
        ])
    }

    func testJellybeansDefaultPaletteUsesPastels() {
        XCTAssertEqual(SoftwareLightingPresetID.jellybeans.label, "Jellybeans")
        XCTAssertEqual(SoftwareLightingPresetID.jellybeans.defaultPalette, [
            RGBPatch(r: 255, g: 142, b: 170),
            RGBPatch(r: 255, g: 194, b: 123),
            RGBPatch(r: 255, g: 239, b: 139),
            RGBPatch(r: 151, g: 231, b: 176),
            RGBPatch(r: 128, g: 219, b: 236),
            RGBPatch(r: 177, g: 161, b: 255),
            RGBPatch(r: 239, g: 157, b: 244),
        ])
    }

    func testFlameTimingVariesAcrossCells() {
        let request = SoftwareLightingEffectRequest(presetID: .flame)
        let samples = stride(from: 0.0, through: 2.0, by: 0.1).map { elapsed in
            SoftwareLightingRenderer.render(
                request: request,
                layout: .basiliskV3ProUSB,
                elapsedTime: elapsed
            )
        }
        let framePairs = zip(samples, samples.dropFirst())
        let firstCellChanges = framePairs.filter { $0.colors[2] != $1.colors[2] }.count
        let secondCellChanges = zip(samples, samples.dropFirst()).filter { $0.colors[7] != $1.colors[7] }.count

        XCTAssertNotEqual(firstCellChanges, secondCellChanges)
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

    func testAnimatedPresetsMoveOverTime() {
        for preset in SoftwareLightingPresetID.allCases {
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
}
