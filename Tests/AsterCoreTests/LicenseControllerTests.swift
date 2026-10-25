import Foundation
import XCTest
@testable import AsterCore

@MainActor final class LicenseControllerTests: XCTestCase {
    private let configuration = DodoConfiguration(environment: .test, businessID: "bus_aster", productID: "prod_aster")
    private let verifiedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testActivationSavesProvenanceAndValidatesTheSpecificInstance() async {
        let store = MemoryLicenseStore()
        let client = FakeLicenseClient()
        let controller = controller(store, client)
        await controller.activate("  purchased-key\n")
        XCTAssertTrue(controller.isPro)
        XCTAssertEqual(store.record?.key, "purchased-key")
        XCTAssertEqual(store.record?.businessID, configuration.businessID)
        XCTAssertEqual(store.record?.productID, configuration.productID)
        XCTAssertEqual(store.savedRecords.count, 2)
        XCTAssertNil(store.savedRecords.first?.lastValidatedAt)
        XCTAssertEqual(store.savedRecords.last?.lastValidatedAt, verifiedDate)
        let requests = await client.validations
        XCTAssertEqual(requests.map(\.instance), ["lki_mac"])
        XCTAssertEqual(requests.map(\.key), ["purchased-key"])
        let names = await client.activationNames
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.first?.hasPrefix("Aster Mac ") == true)
    }

    func testWrongMerchantWrongProductAndMissingProductNeverUnlockAndReleaseSlot() async {
        for activation in [DodoActivation(instanceID: "lki_foreign", businessID: "bus_someone", productID: "prod_aster"),
                           DodoActivation(instanceID: "lki_foreign", businessID: "bus_aster", productID: "prod_other"),
                           DodoActivation(instanceID: "lki_foreign", businessID: "bus_aster", productID: nil)] {
            let store = MemoryLicenseStore()
            let client = FakeLicenseClient(activation: activation)
            let controller = controller(store, client)
            await controller.activate("foreign-key")
            XCTAssertFalse(controller.isPro)
            XCTAssertNil(store.record)
            let deactivations = await client.deactivations
            let validations = await client.validations
            XCTAssertEqual(deactivations.map(\.instance), ["lki_foreign"])
            XCTAssertTrue(validations.isEmpty)
            XCTAssertNotNil(controller.errorMessage)
        }
    }

    func testNoConfigurationAndInvalidInputDoNotContactDodo() async {
        let client = FakeLicenseClient()
        let controller = LicenseController(configuration: nil, store: MemoryLicenseStore(), client: client, requiresLicense: true)
        await controller.activate("a-key")
        XCTAssertFalse(controller.isPro)
        XCTAssertNil(controller.checkoutURL)
        let configured = self.controller(MemoryLicenseStore(), client)
        for input in ["   ", "key\ninside", String(repeating: "x", count: 513)] {
            await configured.activate(input)
        }
        let activations = await client.activationNames
        XCTAssertTrue(activations.isEmpty)
    }

    func testActivationLimitDoesNotCreateAnEntitlement() async {
        let client = FakeLicenseClient(activationError: .activationLimit)
        let store = MemoryLicenseStore()
        let controller = controller(store, client)
        await controller.activate("another-mac-key")
        XCTAssertFalse(controller.isPro)
        XCTAssertFalse(controller.hasSavedLicense)
        XCTAssertTrue(controller.errorMessage?.contains("Mac limit") == true)
    }

    func testPendingActivationCanRetryWithoutConsumingAnotherSlot() async {
        let client = FakeLicenseClient(validation: .failure(.unavailable))
        let store = MemoryLicenseStore()
        let controller = controller(store, client)
        await controller.activate("purchased-key")
        XCTAssertTrue(controller.hasSavedLicense)
        XCTAssertFalse(controller.isPro)
        XCTAssertNil(store.record?.lastValidatedAt)
        await client.setValidation(.success(true))
        await controller.activate("purchased-key")
        XCTAssertTrue(controller.isPro)
        let activations = await client.activationNames
        XCTAssertEqual(activations.count, 1)
    }

    func testOfflineGraceExpiresAndClockRollbackDoesNotExtendIt() async {
        let clock = LicenseTestClock(verifiedDate)
        let store = MemoryLicenseStore(record: record())
        let client = FakeLicenseClient(validation: .failure(.unavailable))
        let controller = LicenseController(configuration: configuration, store: store, client: client, now: { clock.date }, requiresLicense: true)
        await controller.refresh()
        XCTAssertTrue(controller.isPro)
        XCTAssertEqual(store.record?.lastValidatedAt, verifiedDate)
        clock.date = verifiedDate.addingTimeInterval(LicenseController.offlineGrace)
        XCTAssertFalse(controller.isPro)
        clock.date = verifiedDate.addingTimeInterval(-301)
        XCTAssertFalse(controller.isPro)
        clock.date = verifiedDate.addingTimeInterval(LicenseController.offlineGrace - 1)
        XCTAssertTrue(controller.isPro)
    }

    func testRevocationImmediatelyLocksAndSurvivesRestart() async {
        for validation in [Result<Bool, DodoLicenseError>.success(false), .failure(.invalidLicense), .failure(.notFound)] {
            let store = MemoryLicenseStore(record: record())
            let client = FakeLicenseClient(validation: validation)
            let controller = controller(store, client)
            XCTAssertTrue(controller.isPro)
            await controller.refresh()
            XCTAssertFalse(controller.isPro)
            XCTAssertEqual(store.record?.revoked, true)
            let restarted = self.controller(store, FakeLicenseClient(validation: .failure(.unavailable)))
            await restarted.refresh()
            XCTAssertFalse(restarted.isPro)
            XCTAssertNil(restarted.offlineUntil)
        }
    }

    func testRevocationDeletesOldEntitlementWhenSavingFails() async {
        let store = MemoryLicenseStore(record: record())
        store.failSave = true
        let controller = controller(store, FakeLicenseClient(validation: .success(false)))
        await controller.refresh()
        XCTAssertFalse(controller.isPro)
        XCTAssertNil(store.record)
        XCTAssertFalse(self.controller(store, FakeLicenseClient()).isPro)
    }

    func testIndependentMarkerPreventsRestartResurrectionWhenKeychainSaveAndDeleteFail() async {
        let store = MemoryLicenseStore(record: record())
        store.failSave = true
        store.failDelete = true
        let controller = controller(store, FakeLicenseClient(validation: .success(false)))
        await controller.refresh()
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(store.record?.revoked, false, "Simulated Keychain failure leaves the stale credential behind")
        XCTAssertTrue(store.needsVerification)
        let restarted = self.controller(store, FakeLicenseClient(validation: .failure(.unavailable)))
        await restarted.refresh()
        XCTAssertFalse(restarted.isPro)
        XCTAssertNil(restarted.offlineUntil)
    }

    func testIndependentMarkerClearsOnlyAfterVerifiedResponseIsSaved() async {
        let store = MemoryLicenseStore(record: record())
        store.needsVerification = true
        store.failSave = true
        let controller = controller(store, FakeLicenseClient())
        await controller.refresh()
        XCTAssertFalse(controller.isPro)
        XCTAssertTrue(store.needsVerification)
        store.failSave = false
        await controller.refresh()
        XCTAssertTrue(controller.isPro)
        XCTAssertFalse(store.needsVerification)
    }

    func testFailedMarkerClearKeepsProLockedAfterOtherwiseValidResponse() async {
        let store = MemoryLicenseStore(record: record())
        store.needsVerification = true
        store.failMarkerWrite = true
        let controller = controller(store, FakeLicenseClient())
        await controller.refresh()
        XCTAssertFalse(controller.isPro)
        XCTAssertTrue(store.needsVerification)
    }

    func testFailedInitialSaveReleasesNewActivation() async {
        let store = MemoryLicenseStore()
        store.failSave = true
        let client = FakeLicenseClient()
        let controller = controller(store, client)
        await controller.activate("purchased-key")
        XCTAssertFalse(controller.isPro)
        XCTAssertFalse(controller.hasSavedLicense)
        let releases = await client.deactivations
        XCTAssertEqual(releases.count, 1)
    }

    func testFailedSaveAndReleaseKeepInMemoryInstanceForRetry() async {
        let store = MemoryLicenseStore()
        store.failSave = true
        let client = FakeLicenseClient(deactivationError: .unavailable)
        let controller = controller(store, client)
        await controller.activate("purchased-key")
        XCTAssertTrue(controller.hasSavedLicense)
        XCTAssertFalse(controller.isPro)
        await client.setDeactivationError(nil)
        await controller.deactivate()
        XCTAssertFalse(controller.hasSavedLicense)
    }

    func testFailedTimestampSaveNeverExtendsOfflineGrace() async {
        let store = MemoryLicenseStore(record: record())
        store.failSave = true
        let clock = LicenseTestClock(verifiedDate.addingTimeInterval(LicenseController.offlineGrace + 1))
        let controller = LicenseController(configuration: configuration, store: store, client: FakeLicenseClient(), now: { clock.date }, requiresLicense: true)
        await controller.refresh()
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(controller.lastValidatedAt, verifiedDate)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testDeactivateFailurePreservesInstanceAndSuccessClearsIt() async {
        let store = MemoryLicenseStore(record: record())
        let client = FakeLicenseClient(deactivationError: .unavailable)
        let controller = controller(store, client)
        await controller.deactivate()
        XCTAssertTrue(controller.hasSavedLicense)
        XCTAssertTrue(controller.isPro)
        await client.setDeactivationError(nil)
        await controller.deactivate()
        XCTAssertFalse(controller.hasSavedLicense)
        XCTAssertFalse(controller.isPro)
        XCTAssertNil(store.record)
    }

    func testDeactivateAlreadyMissingInstanceClearsLocalKey() async {
        let store = MemoryLicenseStore(record: record())
        let controller = controller(store, FakeLicenseClient(deactivationError: .notFound))
        await controller.deactivate()
        XCTAssertFalse(controller.hasSavedLicense)
        XCTAssertNil(store.record)
    }

    func testDeactivateLocalDeleteFailureStillDisablesAccess() async {
        let store = MemoryLicenseStore(record: record())
        store.failDelete = true
        let controller = controller(store, FakeLicenseClient())
        await controller.deactivate()
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(store.record?.revoked, true)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testMismatchedSavedEnvironmentOrProductNeverUnlocksOrValidates() async {
        for saved in [record(environment: .live), record(product: "prod_other"), record(business: "bus_other")] {
            let client = FakeLicenseClient()
            let controller = controller(MemoryLicenseStore(record: saved), client)
            XCTAssertFalse(controller.isPro)
            await controller.refresh()
            let validations = await client.validations
            XCTAssertTrue(validations.isEmpty)
        }
    }

    func testDifferentEnvironmentCannotBeDeactivatedThroughCurrentEnvironment() async {
        let client = FakeLicenseClient()
        let controller = controller(MemoryLicenseStore(record: record(environment: .live)), client)
        await controller.deactivate()
        let releases = await client.deactivations
        XCTAssertTrue(releases.isEmpty)
    }

    func testWrongProductFailedRollbackPersistsReleaseForRetryAndNeverUnlocks() async {
        let store = MemoryLicenseStore()
        let client = FakeLicenseClient(activation: DodoActivation(instanceID: "lki_other", businessID: "bus_other", productID: "prod_other"),
                                       deactivationError: .unavailable)
        let controller = controller(store, client)
        await controller.activate("foreign-key")
        XCTAssertFalse(controller.isPro)
        XCTAssertTrue(controller.hasSavedLicense)
        XCTAssertEqual(store.record?.instanceID, "lki_other")
        XCTAssertEqual(store.record?.revoked, true)
        let restarted = self.controller(store, client)
        await restarted.refresh()
        XCTAssertFalse(restarted.isPro)
        let validations = await client.validations
        XCTAssertTrue(validations.isEmpty)
        await client.setDeactivationError(nil)
        await restarted.deactivate()
        XCTAssertFalse(restarted.hasSavedLicense)
        XCTAssertNil(store.record)
        XCTAssertFalse(store.needsVerification)
        let releases = await client.deactivations
        XCTAssertEqual(releases.map(\.instance), ["lki_other", "lki_other"])
    }

    func testUnreadableKeychainNeverOverwritesExistingData() async {
        let store = MemoryLicenseStore(record: record())
        store.failLoad = true
        let client = FakeLicenseClient()
        let controller = controller(store, client)
        await controller.activate("replacement-key")
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(store.record?.key, "purchased-key")
        let activations = await client.activationNames
        XCTAssertTrue(activations.isEmpty)
    }

    func testDifferentKeyCannotOverwriteExistingActivation() async {
        let store = MemoryLicenseStore(record: record())
        let client = FakeLicenseClient()
        let controller = controller(store, client)
        await controller.activate("other-key")
        XCTAssertEqual(store.record?.key, "purchased-key")
        let activations = await client.activationNames
        XCTAssertTrue(activations.isEmpty)
    }

    func testConcurrentActivationOnlyConsumesOneSlot() async {
        let client = FakeLicenseClient(activationDelay: 20_000_000)
        let controller = controller(MemoryLicenseStore(), client)
        async let first: Void = controller.activate("purchased-key")
        async let second: Void = controller.activate("purchased-key")
        _ = await (first, second)
        let activations = await client.activationNames
        XCTAssertEqual(activations.count, 1)
        XCTAssertTrue(controller.isPro)
    }

    private func controller(_ store: MemoryLicenseStore, _ client: FakeLicenseClient) -> LicenseController {
        let date = verifiedDate
        return LicenseController(configuration: configuration, store: store, client: client, now: { date }, requiresLicense: true)
    }

    private func record(environment: DodoEnvironment = .test, product: String = "prod_aster", business: String = "bus_aster") -> LicenseRecord {
        LicenseRecord(key: "purchased-key", instanceID: "lki_mac", businessID: business, productID: product,
                      environment: environment, lastValidatedAt: verifiedDate)
    }
}

@MainActor private final class LicenseTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor private final class MemoryLicenseStore: LicenseStore {
    var record: LicenseRecord?
    var savedRecords: [LicenseRecord] = []
    var failLoad = false
    var failSave = false
    var failDelete = false
    var needsVerification = false
    var failMarkerWrite = false
    enum Failure: Error { case unavailable }

    init(record: LicenseRecord? = nil) { self.record = record }
    func load() throws -> LicenseRecord? {
        if failLoad { throw Failure.unavailable }
        return record
    }
    func save(_ record: LicenseRecord) throws {
        if failSave { throw Failure.unavailable }
        self.record = record
        savedRecords.append(record)
    }
    func delete() throws {
        if failDelete { throw Failure.unavailable }
        record = nil
    }
    func requiresOnlineVerification() throws -> Bool { needsVerification }
    func setRequiresOnlineVerification(_ required: Bool) throws {
        if failMarkerWrite { throw Failure.unavailable }
        needsVerification = required
    }
}

private actor FakeLicenseClient: DodoLicenseClient {
    struct InstanceRequest: Sendable { let key: String; let instance: String }
    let activation: DodoActivation
    let activationError: DodoLicenseError?
    let activationDelay: UInt64
    var validation: Result<Bool, DodoLicenseError>
    var deactivationError: DodoLicenseError?
    private(set) var activationNames: [String] = []
    private(set) var validations: [InstanceRequest] = []
    private(set) var deactivations: [InstanceRequest] = []

    init(activation: DodoActivation = DodoActivation(instanceID: "lki_mac", businessID: "bus_aster", productID: "prod_aster"),
         activationError: DodoLicenseError? = nil, validation: Result<Bool, DodoLicenseError> = .success(true),
         deactivationError: DodoLicenseError? = nil, activationDelay: UInt64 = 0) {
        self.activation = activation
        self.activationError = activationError
        self.validation = validation
        self.deactivationError = deactivationError
        self.activationDelay = activationDelay
    }
    func activate(key: String, name: String) async throws -> DodoActivation {
        activationNames.append(name)
        if activationDelay > 0 { try await Task.sleep(nanoseconds: activationDelay) }
        if let activationError { throw activationError }
        return activation
    }
    func validate(key: String, instanceID: String) async throws -> Bool {
        validations.append(InstanceRequest(key: key, instance: instanceID))
        return try validation.get()
    }
    func deactivate(key: String, instanceID: String) async throws {
        deactivations.append(InstanceRequest(key: key, instance: instanceID))
        if let deactivationError { throw deactivationError }
    }
    func setValidation(_ value: Result<Bool, DodoLicenseError>) { validation = value }
    func setDeactivationError(_ value: DodoLicenseError?) { deactivationError = value }
}
