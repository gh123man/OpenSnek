/// Exercises V3 pro USB feature sweep UI behavior.
final class V3ProUSBFeatureSweepUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = FeatureSweep(testCase: self, configuration: .v3ProUSB)

    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3ProUSBFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
