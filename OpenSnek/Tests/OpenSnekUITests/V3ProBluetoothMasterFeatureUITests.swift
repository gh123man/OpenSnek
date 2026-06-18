final class V3ProBluetoothMasterFeatureUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = MasterFeatureSweep(testCase: self, configuration: .v3ProBluetooth)

    override var expectedScope: HardwareDeviceScope {
        .v3ProBluetooth
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3ProBluetoothMasterFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
