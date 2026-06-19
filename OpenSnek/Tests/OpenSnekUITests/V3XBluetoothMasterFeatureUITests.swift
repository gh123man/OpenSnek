final class V3XBluetoothMasterFeatureUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = MasterFeatureSweep(testCase: self, configuration: .v3XBluetooth)

    override var expectedScope: HardwareDeviceScope {
        .v3XBluetooth
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3XBluetoothMasterFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
