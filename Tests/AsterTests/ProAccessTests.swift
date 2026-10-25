import XCTest
import AsterCore
@testable import Aster

@MainActor
final class ProAccessTests: XCTestCase {
    private let configuration = DodoConfiguration(environment: .test, businessID: "test_business", productID: "test_product")
    private let verifiedDate = Date(timeIntervalSince1970: 1_790_000_000)

    func testDefaultFreeReleaseUnlocksFeatureGatesWithoutConfigurationOrReadableKeychain() {
        let store = AccessTestStore()
        store.failAccess = true
        let license = LicenseController(configuration: nil, store: store)
        let cleanup = CleanupState(license: license)

        XCTAssertFalse(AsterAccessPolicy.requiresLicense)
        XCTAssertTrue(license.isPro)
        XCTAssertTrue(cleanup.hasProAccess)
        XCTAssertFalse(license.hasSavedLicense)
        XCTAssertNil(license.checkoutURL)
        XCTAssertNil(license.errorMessage)
        XCTAssertEqual(store.accessCount, 0)
    }

    func testFreeReleaseCanCleanOnlyAfterPreparingAndConfirmingReview() async throws {
        let license = LicenseController(configuration: nil, store: AccessTestStore())
        let (cleanup, file, directory, moves) = try makeCleanup(license: license)
        defer { try? FileManager.default.removeItem(at: directory) }

        cleanup.confirmTrash()
        XCTAssertFalse(cleanup.isTrashing)
        XCTAssertEqual(moves.count, 0, "Free access must not bypass the required preview.")
        XCTAssertEqual(cleanup.queue.count, 1)

        cleanup.prepareReview()
        try await waitForPreview(cleanup)
        XCTAssertTrue(cleanup.canConfirm)
        XCTAssertEqual(cleanup.selectedCount, 1)
        XCTAssertEqual(moves.count, 0, "Preparing a review must not move any files.")

        cleanup.confirmTrash()
        for _ in 0..<200 where cleanup.isTrashing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cleanup.isTrashing)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(cleanup.results.first?.status, .moved)
        XCTAssertTrue(cleanup.queue.isEmpty)
        // The injected mover records calls only. No personal Trash is used.
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFreeReleaseHonorsDeselectionInTheCleanupReview() async throws {
        let license = LicenseController(configuration: nil, store: AccessTestStore())
        let (cleanup, file, directory, moves) = try makeCleanup(license: license)
        defer { try? FileManager.default.removeItem(at: directory) }
        cleanup.prepareReview()
        try await waitForPreview(cleanup)
        let item = try XCTUnwrap(cleanup.review?.items.first)
        cleanup.togglePreviewItem(id: item.id)

        XCTAssertFalse(cleanup.canConfirm)
        cleanup.confirmTrash()
        XCTAssertFalse(cleanup.isTrashing)
        XCTAssertEqual(moves.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFreeReleaseIgnoresOldActivationAndNeverContactsLicenseServices() async {
        let store = AccessTestStore(record: record())
        store.failAccess = true
        let client = AccessTestClient()
        let date = verifiedDate.addingTimeInterval(LicenseController.offlineGrace + 1)
        let license = LicenseController(configuration: configuration, store: store, client: client, now: { date })

        await license.refresh()
        await license.activate("obsolete-license-key")
        await license.deactivate()

        XCTAssertTrue(license.isPro)
        XCTAssertFalse(license.hasSavedLicense)
        XCTAssertNil(license.checkoutURL)
        XCTAssertNil(license.errorMessage)
        XCTAssertEqual(store.accessCount, 0, "The free release must not read or mutate old credentials.")
        XCTAssertEqual(store.record?.key, "test-only-license")
        let networkCalls = await client.callCount
        XCTAssertEqual(networkCalls, 0)
    }

    func testExplicitLicensedModeStillBlocksUnactivatedCleanup() async throws {
        let license = LicenseController(configuration: configuration, store: AccessTestStore(), requiresLicense: true)
        let (cleanup, file, directory, moves) = try makeCleanup(license: license)
        defer { try? FileManager.default.removeItem(at: directory) }
        cleanup.prepareReview()
        try await waitForPreview(cleanup)

        XCTAssertFalse(license.isPro)
        XCTAssertTrue(cleanup.canConfirm)
        cleanup.confirmTrash()
        XCTAssertFalse(cleanup.isTrashing)
        XCTAssertNotNil(cleanup.errorMessage)
        XCTAssertEqual(moves.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(cleanup.queue.count, 1)
    }

    func testExplicitLicensedModeRechecksExpiryAtCleanupConfirmation() async throws {
        let clock = AccessTestClock(date: verifiedDate)
        let license = LicenseController(configuration: configuration, store: AccessTestStore(record: record()),
                                        now: { clock.date }, requiresLicense: true)
        let (cleanup, file, directory, moves) = try makeCleanup(license: license)
        defer { try? FileManager.default.removeItem(at: directory) }
        cleanup.prepareReview()
        try await waitForPreview(cleanup)
        XCTAssertTrue(license.isPro)

        clock.date.addTimeInterval(LicenseController.offlineGrace + 1)
        cleanup.confirmTrash()

        XCTAssertFalse(license.isPro)
        XCTAssertFalse(cleanup.isTrashing)
        XCTAssertEqual(moves.count, 0)
        XCTAssertNotNil(cleanup.review)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(cleanup.queue.count, 1)
    }

    private func record() -> LicenseRecord {
        LicenseRecord(key: "test-only-license", instanceID: "test-instance", businessID: configuration.businessID,
                      productID: configuration.productID, environment: .test, lastValidatedAt: verifiedDate)
    }

    private func makeCleanup(license: LicenseController) throws -> (CleanupState, URL, URL, AccessTestMoves) {
        // Use the physical path: macOS temporaryDirectory may return /var,
        // whose symlink ancestor is intentionally refused by cleanup.
        let directory = URL(fileURLWithPath: "/private/tmp/aster-access-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fixture.txt")
        try Data("isolated test fixture".utf8).write(to: file)
        let moves = AccessTestMoves()
        let service = TrashService(policy: .init(allowedRoots: [directory]), mover: { url in
            moves.record()
            return url
        })
        let cleanup = CleanupState(license: license, service: service)
        cleanup.add(CleanupCandidate(url: file, title: file.lastPathComponent, reason: "Test fixture", kind: "File",
                                     symbol: "doc", logicalSize: 21, ownerBundleID: nil))
        return (cleanup, file, directory, moves)
    }

    private func waitForPreview(_ cleanup: CleanupState) async throws {
        for _ in 0..<200 where cleanup.isPreparing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(cleanup.review)
        XCTAssertNil(cleanup.review?.items.first?.blockedReason)
    }
}

@MainActor private final class AccessTestStore: LicenseStore {
    enum Failure: Error { case unavailable }
    var record: LicenseRecord?
    var failAccess = false
    private(set) var accessCount = 0
    private var mustVerify = false
    init(record: LicenseRecord? = nil) { self.record = record }
    private func recordAccess() throws {
        accessCount += 1
        if failAccess { throw Failure.unavailable }
    }
    func load() throws -> LicenseRecord? {
        try recordAccess()
        return record
    }
    func save(_ record: LicenseRecord) throws {
        try recordAccess()
        self.record = record
    }
    func delete() throws {
        try recordAccess()
        record = nil
    }
    func requiresOnlineVerification() throws -> Bool {
        try recordAccess()
        return mustVerify
    }
    func setRequiresOnlineVerification(_ required: Bool) throws {
        try recordAccess()
        mustVerify = required
    }
}

private actor AccessTestClient: DodoLicenseClient {
    private(set) var callCount = 0
    func activate(key: String, name: String) async throws -> DodoActivation {
        callCount += 1
        throw DodoLicenseError.unavailable
    }
    func validate(key: String, instanceID: String) async throws -> Bool {
        callCount += 1
        throw DodoLicenseError.unavailable
    }
    func deactivate(key: String, instanceID: String) async throws {
        callCount += 1
        throw DodoLicenseError.unavailable
    }
}

@MainActor private final class AccessTestClock {
    var date: Date
    init(date: Date) { self.date = date }
}

private final class AccessTestMoves: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}
