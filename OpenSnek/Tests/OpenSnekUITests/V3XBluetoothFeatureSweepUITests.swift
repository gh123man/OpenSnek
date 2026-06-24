/// Exercises V3 X Bluetooth feature sweep UI behavior.
final class V3XBluetoothFeatureSweepUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = FeatureSweep(testCase: self, configuration: .v3XBluetooth)

    override var expectedScope: HardwareDeviceScope {
        .v3XBluetooth
    }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
    }

    func testV3XBluetoothFeatureSweepDoesNotCrossInterfere() throws {
        try sweep.run()
    }
}
