final class V3ProUSBMasterFeatureUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = MasterFeatureSweep(testCase: self, configuration: .v3ProUSB)

    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3ProUSBMasterFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
