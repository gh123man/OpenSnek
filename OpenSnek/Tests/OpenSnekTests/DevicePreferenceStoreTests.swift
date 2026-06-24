import XCTest
import OpenSnekAppSupport
import OpenSnekCore

/// Exercises device preference store behavior.
final class DevicePreferenceStoreTests: XCTestCase {
    func testOpenSnekButtonProfileLibrarySupportsSaveUpdateAndDelete() {
        let suiteName = "DevicePreferenceStoreTests.Library.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let saved = store.saveOpenSnekButtonProfile(
            name: "Travel",
            bindings: [
                4: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 9, turboEnabled: false, turboRate: 0x8E)
            ]
        )

        XCTAssertEqual(store.loadOpenSnekButtonProfiles().map(\.name), ["Travel"])
        XCTAssertEqual(store.loadOpenSnekButtonProfiles().first?.bindings[4]?.hidKey, 9)

        let updated = store.updateOpenSnekButtonProfile(
            id: saved.id,
            name: "Travel 2",
            bindings: [
                4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
            ]
        )

        XCTAssertEqual(updated?.name, "Travel 2")
        XCTAssertEqual(store.loadOpenSnekButtonProfiles().first?.bindings[4]?.kind, .mouseForward)

        store.deleteOpenSnekButtonProfile(id: saved.id)
        XCTAssertTrue(store.loadOpenSnekButtonProfiles().isEmpty)
    }

    func testOpenSnekLocalProfileLibrarySupportsCreateCopyRenameAndDelete() {
        let suiteName = "DevicePreferenceStoreTests.LocalLibrary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let content = OpenSnekLocalProfileContent(
            dpi: OnboardDPIProfileSnapshot(
                scalar: DpiPair(x: 800, y: 800),
                activeStage: 0,
                pairs: [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600)]
            ),
            buttonBindings: [
                4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
            ],
            brightnessByLEDID: [1: 72],
            staticColorByLEDID: [1: RGBPatch(r: 10, g: 20, b: 30)],
            scrollMode: 1,
            scrollAcceleration: true,
            scrollSmartReel: false
        )

        let saved = store.createOpenSnekLocalProfile(name: " Travel ", content: content)
        let copied = store.createOpenSnekLocalProfile(name: "Copy", copying: saved.id)

        XCTAssertEqual(store.loadOpenSnekLocalProfiles().map(\.name), ["Copy", "Travel"])
        XCTAssertEqual(copied.content, content)

        let renamed = store.updateOpenSnekLocalProfile(id: saved.id, name: "Travel 2")

        XCTAssertEqual(renamed?.name, "Travel 2")
        XCTAssertEqual(store.loadOpenSnekLocalProfiles().first(where: { $0.id == saved.id })?.name, "Travel 2")

        store.deleteOpenSnekLocalProfile(id: saved.id)

        XCTAssertEqual(store.loadOpenSnekLocalProfiles().map(\.id), [copied.id])
    }

    func testOpenSnekLocalProfileLibraryMigratesButtonOnlyProfilesOnce() {
        let suiteName = "DevicePreferenceStoreTests.LocalMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let legacy = store.saveOpenSnekButtonProfile(
            name: "Legacy Buttons",
            bindings: [
                5: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 80, turboEnabled: false, turboRate: 0x8E)
            ]
        )

        let migrated = store.loadOpenSnekLocalProfiles()
        let loadedAgain = store.loadOpenSnekLocalProfiles()

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.id, legacy.id)
        XCTAssertEqual(migrated.first?.name, "Legacy Buttons")
        XCTAssertEqual(migrated.first?.content.buttonBindings[5]?.hidKey, 80)
        XCTAssertNil(migrated.first?.content.dpi)
        XCTAssertEqual(loadedAgain.count, 1)
    }

    func testOpenSnekLocalProfileUpsertByOnboardUUIDPreservesLocalRecordID() {
        let suiteName = "DevicePreferenceStoreTests.UUIDUpsert.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-local-uuid-upsert",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "LOCAL-UUID-UPSERT",
            firmware: nil,
            profile_id: .basiliskV3Pro
        )
        let onboardIdentifier = UUID()
        let firstSnapshot = OnboardProfileSnapshot(
            profileID: 2,
            metadata: OnboardProfileMetadata(identifier: onboardIdentifier, name: "Desk"),
            dpi: OnboardDPIProfileSnapshot(
                scalar: DpiPair(x: 800, y: 800),
                activeStage: 0,
                pairs: [DpiPair(x: 800, y: 800)]
            ),
            buttonBindings: [
                4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
            ],
            brightnessByLEDID: [1: 64],
            staticColorByLEDID: [1: RGBPatch(r: 1, g: 2, b: 3)],
            scrollMode: 0,
            scrollAcceleration: false,
            scrollSmartReel: true
        )
        let updatedSnapshot = OnboardProfileSnapshot(
            profileID: 2,
            metadata: OnboardProfileMetadata(identifier: onboardIdentifier, name: "Desk Edited"),
            dpi: OnboardDPIProfileSnapshot(
                scalar: DpiPair(x: 1600, y: 1600),
                activeStage: 1,
                pairs: [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600)]
            ),
            buttonBindings: [
                4: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 80, turboEnabled: true, turboRate: 75)
            ],
            brightnessByLEDID: [1: 128],
            staticColorByLEDID: [1: RGBPatch(r: 9, g: 8, b: 7)],
            scrollMode: 1,
            scrollAcceleration: true,
            scrollSmartReel: false
        )

        let first = store.upsertOpenSnekLocalProfile(from: firstSnapshot, device: device)
        let updated = store.upsertOpenSnekLocalProfile(from: updatedSnapshot, device: device)
        let profiles = store.loadOpenSnekLocalProfiles()

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.onboardIdentifier, onboardIdentifier)
        XCTAssertEqual(profiles.first?.sourceDeviceProfileID, .basiliskV3Pro)
        XCTAssertEqual(profiles.first?.sourceTransport, .usb)
        XCTAssertEqual(profiles.first?.name, "Desk Edited")
        XCTAssertEqual(profiles.first?.content.dpi?.values, [800, 1600])
        XCTAssertEqual(profiles.first?.content.buttonBindings[4]?.hidKey, 80)
        XCTAssertEqual(profiles.first?.content.brightnessByLEDID[1], 128)
        XCTAssertEqual(profiles.first?.content.staticColorByLEDID[1], RGBPatch(r: 9, g: 8, b: 7))
        XCTAssertEqual(profiles.first?.content.scrollMode, 1)
    }

    func testOpenSnekLocalProfileUpsertBySyntheticSlotKeyPreservesLocalRecordID() {
        let suiteName = "DevicePreferenceStoreTests.SyntheticUpsert.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "bt-local-synthetic-upsert",
            vendor_id: 0x068E,
            product_id: 0x00BA,
            product_name: "Basilisk V3 X HyperSpeed",
            transport: .bluetooth,
            path_b64: "",
            serial: "LOCAL-SYNTHETIC-UPSERT",
            firmware: nil,
            profile_id: .basiliskV3XHyperspeed
        )
        let sourceKey = DevicePreferenceStore.localProfileSyntheticSourceKey(device: device, slot: 1)
        let first = store.upsertOpenSnekLocalProfile(
            name: "This Mouse",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 800, y: 800),
                    activeStage: 0,
                    pairs: [DpiPair(x: 800, y: 800)]
                ),
                brightnessByLEDID: [1: 999],
                scrollMode: 7
            ),
            syntheticSourceKey: sourceKey,
            device: device
        )
        let updated = store.upsertOpenSnekLocalProfile(
            name: "This Mouse Edited",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 1200, y: 1200),
                    activeStage: 0,
                    pairs: [DpiPair(x: 1200, y: 1200)]
                ),
                buttonBindings: [
                    5: ButtonBindingDraft(kind: .mouseBack, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
                ]
            ),
            syntheticSourceKey: sourceKey,
            device: device
        )
        let profiles = store.loadOpenSnekLocalProfiles()

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertNil(profiles.first?.onboardIdentifier)
        XCTAssertEqual(profiles.first?.syntheticSourceKey, sourceKey)
        XCTAssertEqual(profiles.first?.name, "This Mouse Edited")
        XCTAssertEqual(profiles.first?.sourceDeviceProfileID, .basiliskV3XHyperspeed)
        XCTAssertEqual(profiles.first?.sourceTransport, .bluetooth)
        XCTAssertEqual(first.content.brightnessByLEDID[1], 255)
        XCTAssertEqual(first.content.scrollMode, 1)
        XCTAssertEqual(profiles.first?.content.dpi?.values, [1200])
        XCTAssertEqual(profiles.first?.content.buttonBindings[5]?.kind, .mouseBack)
    }

    func testHyperspeedSyntheticLocalProfileKeySurvivesSerialChanges() {
        let suiteName = "DevicePreferenceStoreTests.HyperspeedSyntheticKey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let firstDevice = makeHyperspeedLocalProfileDevice(serial: "HYPER-A")
        let reconnectedDevice = makeHyperspeedLocalProfileDevice(serial: "HYPER-B")
        let firstKey = DevicePreferenceStore.localProfileSyntheticSourceKey(device: firstDevice, slot: 1)
        let reconnectedKey = DevicePreferenceStore.localProfileSyntheticSourceKey(device: reconnectedDevice, slot: 1)

        XCTAssertEqual(firstKey, reconnectedKey)

        let first = store.upsertOpenSnekLocalProfile(
            name: "This Mouse",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 800, y: 800),
                    activeStage: 0,
                    pairs: [DpiPair(x: 800, y: 800)]
                )
            ),
            syntheticSourceKey: firstKey,
            device: firstDevice
        )
        let updated = store.upsertOpenSnekLocalProfile(
            name: "This Mouse",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 1200, y: 1200),
                    activeStage: 0,
                    pairs: [DpiPair(x: 1200, y: 1200)]
                )
            ),
            syntheticSourceKey: reconnectedKey,
            device: reconnectedDevice
        )
        let profiles = store.loadOpenSnekLocalProfiles()

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.content.dpi?.values, [1200])
    }

    func testButtonBindingPersistencePreservesNonTextKeyboardHidKeys() {
        let suiteName = "DevicePreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "bt-device",
            vendor_id: 0x068E,
            product_id: 0x00BA,
            product_name: "Basilisk V3 X HyperSpeed",
            transport: .bluetooth,
            path_b64: "",
            serial: nil,
            firmware: nil,
            profile_id: .basiliskV3XHyperspeed,
            button_layout: ButtonSlotLayout(
                visibleSlots: DeviceProfiles.basiliskV3XButtonSlots,
                writableSlots: DeviceProfiles.basiliskV3XButtonSlots.map(\.slot),
                documentedSlots: DeviceProfiles.basiliskV3XDocumentedReadOnlySlots
            )
        )

        store.persistButtonBinding(
            ButtonBindingPatch(slot: 5, kind: .keyboardSimple, hidKey: 80, turboEnabled: false, turboRate: nil),
            device: device,
            profile: 1
        )
        store.persistButtonBinding(
            ButtonBindingPatch(slot: 4, kind: .keyboardSimple, hidKey: 224, turboEnabled: true, turboRate: 75),
            device: device,
            profile: 1
        )

        let loaded = store.loadPersistedButtonBindings(device: device, profile: 1)
        XCTAssertEqual(loaded[5]?.kind, .keyboardSimple)
        XCTAssertEqual(loaded[5]?.hidKey, 80)
        XCTAssertEqual(loaded[4]?.kind, .keyboardSimple)
        XCTAssertEqual(loaded[4]?.hidKey, 224)
        XCTAssertEqual(loaded[4]?.turboEnabled, true)
        XCTAssertEqual(loaded[4]?.turboRate, 75)
    }

    func test35KTopDPIButtonPersistsSemanticDefaultAsDefaultKind() {
        let suiteName = "DevicePreferenceStoreTests.35KDefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-35k",
            vendor_id: 0x1532,
            product_id: 0x00CB,
            product_name: "Basilisk V3 35K",
            transport: .usb,
            path_b64: "",
            serial: nil,
            firmware: nil,
            profile_id: .basiliskV335K,
            button_layout: DeviceProfiles.resolve(
                vendorID: 0x1532,
                productID: 0x00CB,
                transport: .usb
            )?.buttonLayout
        )

        store.persistButtonBinding(
            ButtonBindingPatch(slot: 96, kind: .dpiCycle, hidKey: nil, turboEnabled: false, turboRate: nil),
            device: device,
            profile: 1
        )

        let loaded = store.loadPersistedButtonBindings(device: device, profile: 1)
        XCTAssertEqual(loaded[96]?.kind, .default)
    }

    func testConnectBehaviorPersistsPerDevice() {
        let suiteName = "DevicePreferenceStoreTests.ConnectBehavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-connect-behavior",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "CONNECT-BEHAVIOR",
            firmware: nil,
            profile_id: .basiliskV3Pro
        )

        store.persistConnectBehavior(.restoreOpenSnekSettings, device: device)

        XCTAssertEqual(store.loadConnectBehavior(device: device), .restoreOpenSnekSettings)
    }

    func testSelectedLocalProfileIDPersistsPerDevice() {
        let suiteName = "DevicePreferenceStoreTests.SelectedLocalProfile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "bt-selected-local-profile",
            vendor_id: 0x1532,
            product_id: 0x00BA,
            product_name: "Basilisk V3 X HyperSpeed",
            transport: .bluetooth,
            path_b64: "",
            serial: "SELECTED-LOCAL-PROFILE",
            firmware: nil,
            profile_id: .basiliskV3XHyperspeed
        )
        let profileID = UUID()

        store.persistSelectedLocalProfileID(profileID, device: device)

        XCTAssertEqual(store.loadSelectedLocalProfileID(device: device), profileID)

        store.persistSelectedLocalProfileID(nil, device: device)

        XCTAssertNil(store.loadSelectedLocalProfileID(device: device))
    }

    func testSoftwareLightingPreferencesPersistPerDevice() {
        let suiteName = "DevicePreferenceStoreTests.SoftwareLighting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-software-lighting-preferences",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "SOFTWARE-LIGHTING-PREFS",
            firmware: nil,
            profile_id: .basiliskV3Pro
        )
        let request = SoftwareLightingEffectRequest(
            presetID: .aurora,
            framesPerSecond: 24,
            intensity: 0.75,
            speed: 1.35,
            palette: [
                RGBPatch(r: 11, g: 22, b: 33),
                RGBPatch(r: 44, g: 55, b: 66)
            ]
        )

        XCTAssertFalse(store.loadSoftwareLightingApplyOnConnect(device: device))

        store.persistSoftwareLightingApplyOnConnect(true, device: device)
        store.persistSoftwareLightingRequest(request, device: device)

        XCTAssertTrue(store.loadSoftwareLightingApplyOnConnect(device: device))
        XCTAssertEqual(store.loadPersistedSoftwareLightingRequest(device: device), request)
    }

    func testDeviceSettingsSnapshotRoundTrips() {
        let suiteName = "DevicePreferenceStoreTests.SettingsSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-settings-snapshot",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "SETTINGS-SNAPSHOT",
            firmware: nil,
            profile_id: .basiliskV3Pro
        )
        let snapshot = PersistedDeviceSettingsSnapshot(
            stageCount: 3,
            stageValues: [800, 1600, 3200],
            stagePairs: [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600), DpiPair(x: 3200, y: 3200)],
            activeStage: 2,
            pollRate: 500,
            sleepTimeout: 420,
            lowBatteryThresholdRaw: 0x24,
            scrollMode: 1,
            scrollAcceleration: true,
            scrollSmartReel: false,
            ledBrightness: 77,
            primaryLightingColor: RGBColor(r: 10, g: 20, b: 30),
            lightingEffect: LightingEffectPatch(kind: .wave, primary: RGBPatch(r: 10, g: 20, b: 30), waveDirection: .right),
            usbLightingZoneID: "logo",
            buttonBindings: [
                5: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 80, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ]
        )

        store.persistDeviceSettingsSnapshot(snapshot, device: device)

        XCTAssertEqual(store.loadPersistedDeviceSettingsSnapshot(device: device), snapshot)
    }

    func testDisabledSettingStoragePreservesPreviouslyStoredDeviceState() {
        let suiteName = "DevicePreferenceStoreTests.SettingStorageDisabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DevicePreferenceStore(defaults: defaults)
        let device = MouseDevice(
            id: "usb-storage-gated-device",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "STORAGE-GATED",
            firmware: nil,
            profile_id: .basiliskV3Pro,
            button_layout: DeviceProfiles.resolve(
                vendorID: 0x1532,
                productID: 0x00AB,
                transport: .usb
            )?.buttonLayout
        )

        let storedSnapshot = PersistedDeviceSettingsSnapshot(
            stageCount: 3,
            stageValues: [800, 1600, 3200],
            stagePairs: [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600), DpiPair(x: 3200, y: 3200)],
            activeStage: 2,
            pollRate: 500,
            sleepTimeout: 420,
            lowBatteryThresholdRaw: 0x24,
            scrollMode: 1,
            scrollAcceleration: true,
            scrollSmartReel: false,
            ledBrightness: 77,
            primaryLightingColor: RGBColor(r: 10, g: 20, b: 30),
            lightingEffect: nil,
            usbLightingZoneID: "logo",
            buttonBindings: [
                5: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 80, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ]
        )
        store.persistDeviceSettingsSnapshot(storedSnapshot, device: device)
        store.persistLightingColor(RGBColor(r: 12, g: 34, b: 56), device: device, zoneID: "logo")
        let storedSoftwareLightingRequest = SoftwareLightingEffectRequest(
            presetID: .cometChase,
            speed: 1.2,
            palette: [RGBPatch(r: 1, g: 2, b: 3), RGBPatch(r: 4, g: 5, b: 6)]
        )
        store.persistSoftwareLightingApplyOnConnect(true, device: device)
        store.persistSoftwareLightingRequest(storedSoftwareLightingRequest, device: device)
        store.savePersistedButtonBindings(
            device: device,
            bindings: [
                5: ButtonBindingDraft(kind: .keyboardSimple, hidKey: 80, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ],
            profile: 1
        )

        defaults.set(false, forKey: DeveloperRuntimeOptions.settingStorageEnabledDefaultsKey)

        let newSnapshot = PersistedDeviceSettingsSnapshot(
            stageCount: 2,
            stageValues: [400, 6400],
            stagePairs: [DpiPair(x: 400, y: 400), DpiPair(x: 6400, y: 6400)],
            activeStage: 1,
            pollRate: 1000,
            sleepTimeout: 300,
            lowBatteryThresholdRaw: 0x18,
            scrollMode: 0,
            scrollAcceleration: false,
            scrollSmartReel: true,
            ledBrightness: 20,
            primaryLightingColor: RGBColor(r: 200, g: 210, b: 220),
            lightingEffect: LightingEffectPatch(
                kind: .wave,
                primary: RGBPatch(r: 200, g: 210, b: 220),
                waveDirection: .right
            ),
            usbLightingZoneID: "scroll_wheel",
            buttonBindings: [
                5: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ]
        )
        store.persistDeviceSettingsSnapshot(newSnapshot, device: device)
        store.persistLightingColor(RGBColor(r: 99, g: 88, b: 77), device: device, zoneID: "logo")
        store.persistSoftwareLightingApplyOnConnect(false, device: device)
        store.persistSoftwareLightingRequest(
            SoftwareLightingEffectRequest(presetID: .aurora, speed: 0.4),
            device: device
        )
        store.savePersistedButtonBindings(
            device: device,
            bindings: [
                5: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ],
            profile: 1
        )

        XCTAssertEqual(store.loadPersistedDeviceSettingsSnapshot(device: device), storedSnapshot)
        XCTAssertEqual(store.loadPersistedLightingColor(device: device, zoneID: "logo"), RGBColor(r: 12, g: 34, b: 56))
        XCTAssertTrue(store.loadSoftwareLightingApplyOnConnect(device: device))
        XCTAssertEqual(store.loadPersistedSoftwareLightingRequest(device: device), storedSoftwareLightingRequest)
        XCTAssertEqual(store.loadPersistedButtonBindings(device: device, profile: 1)[5]?.kind, .keyboardSimple)
    }
}

private func makeHyperspeedLocalProfileDevice(serial: String) -> MouseDevice {
    MouseDevice(
        id: "bt-local-synthetic-\(serial)",
        vendor_id: 0x068E,
        product_id: 0x00BA,
        product_name: "Basilisk V3 X HyperSpeed",
        transport: .bluetooth,
        path_b64: "",
        serial: serial,
        firmware: nil,
        profile_id: .basiliskV3XHyperspeed
    )
}
