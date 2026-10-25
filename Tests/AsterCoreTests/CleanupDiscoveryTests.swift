import XCTest
import Foundation
import Darwin
@testable import AsterCore

final class CleanupDiscoveryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AsterCleanupDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try FileManager.default.removeItem(at: home) }
    }

    @discardableResult
    private func write(_ path: String, bytes: Int) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func testMeasuresRealMetadataForDirectChildrenAcrossSupportedAreas() async throws {
        try write("Library/Caches/com.acme.editor/blob", bytes: 1_024)
        try write("Library/Caches/com.acme.editor/nested/blob", bytes: 512)
        try write("Library/Logs/Session.log", bytes: 128)
        try write("Library/Developer/Xcode/DerivedData/Project-abc/Build/output", bytes: 2_048)
        try write("Documents/Outside.txt", bytes: 50_000)
        let result = try await CleanupDiscoveryScanner.scan(home: home)

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entries.reduce(0) { $0 + $1.logicalSize }, 3_712)
        let cache = try XCTUnwrap(result.entries.first { $0.area == .caches })
        XCTAssertEqual(cache.logicalSize, 1_536)
        XCTAssertEqual(cache.fileCount, 2)
        XCTAssertEqual(cache.ownerBundleIdentifier, "com.acme.editor")
        XCTAssertNil(cache.blockedReason)
        let developer = try XCTUnwrap(result.entries.first { $0.area == .developer })
        XCTAssertEqual(developer.title, "Project-abc")
        XCTAssertEqual(developer.ownerBundleIdentifier, "com.apple.dt.Xcode")
        XCTAssertTrue(result.entries.allSatisfy { $0.url.path != $0.area.location(in: home).path })
        XCTAssertFalse(result.entries.contains { $0.url.path.contains("Documents") })
    }

    func testAbsentOptionalLocationsAreNotErrors() async throws {
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testAppleDataIsVisibleButBlockedAndGenericNamesHaveNoInferredOwner() async throws {
        try write("Library/Caches/com.apple.Example/cache", bytes: 64)
        try write("Library/Caches/Browser Cache/cache", bytes: 32)
        try write("Library/Logs/com.acme.editor.log", bytes: 16)
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertTrue(result.isComplete)
        let apple = try XCTUnwrap(result.entries.first { $0.title == "com.apple.Example" })
        XCTAssertEqual(apple.ownerBundleIdentifier, "com.apple.Example")
        XCTAssertTrue(try XCTUnwrap(apple.blockedReason).contains("Apple application data"))
        XCTAssertFalse(apple.isPartial)
        let generic = try XCTUnwrap(result.entries.first { $0.title == "Browser Cache" })
        XCTAssertNil(generic.ownerBundleIdentifier)
        let log = try XCTUnwrap(result.entries.first { $0.area == .logs })
        XCTAssertEqual(log.ownerBundleIdentifier, "com.acme.editor")
    }

    func testMemoryLimitOnlyBlocksTheAffectedEntry() async throws {
        for index in 0..<8 { try write("Library/Caches/large/payload-\(index)", bytes: 10) }
        try write("Library/Caches/small/payload", bytes: 16)
        try write("Library/Logs/Small.log", bytes: 32)
        let result = try await CleanupDiscoveryScanner.scan(home: home, maxNodesPerRoot: 4)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.warnings.contains { $0.contains("memory limit") })
        let large = try XCTUnwrap(result.entries.first { $0.title == "large" })
        XCTAssertTrue(large.isPartial)
        XCTAssertNotNil(large.blockedReason)
        let small = try XCTUnwrap(result.entries.first { $0.title == "small" })
        XCTAssertFalse(small.isPartial)
        XCTAssertNil(small.blockedReason)
        let log = try XCTUnwrap(result.entries.first { $0.area == .logs })
        XCTAssertFalse(log.isPartial)
        XCTAssertNil(log.blockedReason)
    }

    func testLinksAreNeverFollowedAndDoNotBlockMeasuredNeighbors() async throws {
        let outside = try write("Outside/private-data", bytes: 8_192)
        try write("Library/Caches/com.acme.editor/data", bytes: 64)
        let alias = CleanupArea.caches.location(in: home).appendingPathComponent("linked-data")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/com.acme.editor/nested-link"), withDestinationURL: outside)
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.entries.count, 1)
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.logicalSize, 64)
        XCTAssertFalse(entry.isPartial)
        XCTAssertNil(entry.blockedReason)
        XCTAssertFalse(result.entries.contains { $0.id == alias.path })
    }

    func testRootAndAncestorLinksAreExcluded() async throws {
        let outside = home.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library"), withDestinationURL: outside)
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Symbolic-link locations are excluded") })
    }

    func testUnreadableChildDoesNotBlockReadableNeighbors() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission fixture requires a non-root user") }
        let file = try write("Library/Caches/restricted/private-data", bytes: 128)
        try write("Library/Caches/available/cache", bytes: 64)
        let restricted = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path) }
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.warnings.isEmpty)
        let unreadable = try XCTUnwrap(result.entries.first { $0.title == "restricted" })
        XCTAssertTrue(unreadable.isPartial)
        XCTAssertNotNil(unreadable.blockedReason)
        let readable = try XCTUnwrap(result.entries.first { $0.title == "available" })
        XCTAssertFalse(readable.isPartial)
        XCTAssertNil(readable.blockedReason)
    }

    func testListingLimitIsExplicitWithoutBlockingAlreadyMeasuredEntries() async throws {
        for index in 0..<4 { try write("Library/Caches/cache-\(index)/payload", bytes: 10) }
        let result = try await CleanupDiscoveryScanner.scan(home: home, maxEntriesPerRoot: 2)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("listing limit") })
        XCTAssertTrue(result.entries.allSatisfy { !$0.isPartial && $0.blockedReason == nil })
    }

    func testExistingToolCacheIsOneFriendlyEntryAndAbsentToolsAreNotInvented() async throws {
        let descriptor = try XCTUnwrap(DeveloperCacheLocations.all.first { $0.relativeHomePath == ".npm/_cacache" })
        try write(descriptor.relativeHomePath + "/opaque-hash/content", bytes: 256)
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.entries.count, 1)
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.title, descriptor.title)
        XCTAssertEqual(entry.url.path, home.appendingPathComponent(descriptor.relativeHomePath).path)
        XCTAssertEqual(entry.logicalSize, 256)
        XCTAssertEqual(entry.area, .developer)
        XCTAssertEqual(entry.note, descriptor.note)
        XCTAssertEqual(entry.documentationURL, descriptor.documentationURL)
    }

    func testVendorManagedToolDataIsVisibleButBlocked() async throws {
        let descriptor = try XCTUnwrap(DeveloperCacheLocations.all.first { $0.cleanupPolicy == .vendorManaged })
        try write(descriptor.relativeHomePath + "/fixture-cache", bytes: 64)
        let result = try await CleanupDiscoveryScanner.scan(home: home)
        let entry = try XCTUnwrap(result.entries.first { $0.url.path == home.appendingPathComponent(descriptor.relativeHomePath).path })
        XCTAssertEqual(entry.logicalSize, 64)
        XCTAssertFalse(entry.isPartial)
        XCTAssertTrue(try XCTUnwrap(entry.blockedReason).contains("own cleanup controls"))
    }

    func testKubernetesDiscoveryExcludesCredentialsAndClusterConfiguration() async throws {
        try write(".kube/cache/discovery/cluster/api", bytes: 128)
        try write(".kube/cache/http/response", bytes: 64)
        try write(".kube/cache/oidc-login/token", bytes: 1_024)
        try write(".kube/config", bytes: 512)
        try write(".minikube/profiles/cluster/config.json", bytes: 512)
        let result = try await CleanupDiscoveryScanner.scan(home: home)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries.reduce(0) { $0 + $1.logicalSize }, 192)
        XCTAssertTrue(result.entries.allSatisfy { $0.url.path.hasSuffix("/discovery") || $0.url.path.hasSuffix("/http") })
        XCTAssertFalse(result.entries.contains { $0.url.path.hasSuffix("/.kube/cache") })
    }

    func testDockerDiscoveryMeasuresLogsWithoutIncludingDiskImagesOrVolumes() async throws {
        try write("Library/Containers/com.docker.docker/Data/log/host/diagnostic.log", bytes: 128)
        try write("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 32_768)
        try write("Library/Containers/com.docker.docker/Data/volumes/private-data", bytes: 8_192)
        let result = try await CleanupDiscoveryScanner.scan(home: home)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.entries.count, 1)
        let logs = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(logs.logicalSize, 128)
        XCTAssertTrue(logs.url.path.hasSuffix("/Data/log"))
        XCTAssertNotNil(logs.blockedReason)
    }

    func testMissingHomeIsNotReportedAsSuccessfulEmptyScan() async throws {
        let result = try await CleanupDiscoveryScanner.scan(home: home.appendingPathComponent("Missing"))
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testCancellationThrowsWithoutReturningMisleadingResults() async throws {
        let selectedHome = home!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CleanupDiscoveryScanner.scan(home: selectedHome)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
