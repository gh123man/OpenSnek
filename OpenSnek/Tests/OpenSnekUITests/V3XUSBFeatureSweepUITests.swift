final class V3XUSBFeatureSweepUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = FeatureSweep(testCase: self, configuration: .v3XUSB)

    override var expectedScope: HardwareDeviceScope {
        .v3XUSB
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3XUSBFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
