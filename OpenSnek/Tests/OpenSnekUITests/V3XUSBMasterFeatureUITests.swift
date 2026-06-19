final class V3XUSBMasterFeatureUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = MasterFeatureSweep(testCase: self, configuration: .v3XUSB)

    override var expectedScope: HardwareDeviceScope {
        .v3XUSB
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3XUSBMasterFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
