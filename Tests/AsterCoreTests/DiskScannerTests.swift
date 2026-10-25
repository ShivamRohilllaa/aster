import XCTest
import Foundation
import Darwin
@testable import AsterCore

final class DiskScannerTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("AsterScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureURL { try FileManager.default.removeItem(at: fixtureURL) }
    }

    @discardableResult
    private func write(_ path: String, count: Int) throws -> URL {
        let url = fixtureURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<count).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    func testAggregatesNestedFilesAndRetainsEmptyDirectories() async throws {
        let first = try write("Projects/App.swift", count: 512)
        let second = try write("Projects/Assets/photo.png", count: 2048)
        let third = try write("notes.pdf", count: 71)
        let empty = fixtureURL.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }

        XCTAssertEqual(snapshot.root.logicalSize, 2631)
        XCTAssertEqual(snapshot.root.fileCount, 3)
        XCTAssertEqual(snapshot.visitedFileCount, 3)
        XCTAssertEqual(snapshot.nodes.count, 7)
        XCTAssertEqual(snapshot.nodes[first.path]?.logicalSize, 512)
        XCTAssertEqual(snapshot.nodes[second.path]?.category, .media)
        XCTAssertEqual(snapshot.nodes[third.path]?.category, .documents)
        XCTAssertEqual(snapshot.nodes[first.deletingLastPathComponent().path]?.logicalSize, 2560)
        XCTAssertEqual(snapshot.nodes[empty.path]?.logicalSize, 0)
        XCTAssertEqual(snapshot.nodes[empty.path]?.children, [])
        XCTAssertFalse(snapshot.isDemo)
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertTrue(snapshot.issues.isEmpty)
        assertConsistent(snapshot)
    }

    func testSymlinksAreShownWithoutFollowingTargetsOrCountingTheirBytes() async throws {
        let file = try write("Actual/payload.bin", count: 16_384)
        let directoryLink = fixtureURL.appendingPathComponent("directory-link")
        let fileLink = fixtureURL.appendingPathComponent("file-link")
        let brokenLink = fixtureURL.appendingPathComponent("broken-link")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: file.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: fixtureURL.appendingPathComponent("does-not-exist"))
        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }

        XCTAssertEqual(snapshot.root.logicalSize, 16_384)
        XCTAssertEqual(snapshot.root.fileCount, 1)
        XCTAssertEqual(snapshot.skippedLinkCount, 3)
        XCTAssertEqual(snapshot.nodes[directoryLink.path]?.isSymbolicLink, true)
        XCTAssertEqual(snapshot.nodes[fileLink.path]?.logicalSize, 0)
        XCTAssertEqual(snapshot.nodes[brokenLink.path]?.allocatedSize, 0)
        XCTAssertNil(snapshot.nodes[directoryLink.appendingPathComponent("payload.bin").path])
        assertConsistent(snapshot)
    }

    func testHardLinksCountLogicalNamesButAllocateBytesOnce() async throws {
        let file = try write("original.dat", count: 16_384)
        let link = fixtureURL.appendingPathComponent("same-inode.dat")
        try FileManager.default.linkItem(at: file, to: link)
        var info = stat()
        XCTAssertEqual(file.withUnsafeFileSystemRepresentation { Darwin.lstat($0!, &info) }, 0)
        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }

        XCTAssertEqual(snapshot.root.logicalSize, 32_768)
        XCTAssertEqual(snapshot.root.allocatedSize, Int64(info.st_blocks) * 512)
        XCTAssertEqual(snapshot.root.fileCount, 2)
        XCTAssertEqual([snapshot.nodes[file.path]!.allocatedSize, snapshot.nodes[link.path]!.allocatedSize].filter { $0 > 0 }.count, 1)
        assertConsistent(snapshot)
    }

    func testItemLimitReturnsAnExplicitlyPartialConsistentSnapshot() async throws {
        for index in 0..<10 { try write("item-\(index).bin", count: 100) }
        let snapshot = try await DiskScanner(maxNodeCount: 4, maxIssueCount: 2).scan(url: fixtureURL) { _ in }

        XCTAssertEqual(snapshot.nodes.count, 4)
        XCTAssertEqual(snapshot.root.fileCount, 3)
        XCTAssertEqual(snapshot.root.logicalSize, 300)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertTrue(snapshot.issues.contains { $0.message.contains("memory limit") })
        assertConsistent(snapshot)
    }

    func testEmptyDirectoryReturnsValidZeroSnapshot() async throws {
        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }
        XCTAssertEqual(snapshot.nodes.count, 1)
        XCTAssertEqual(snapshot.root.logicalSize, 0)
        XCTAssertEqual(snapshot.root.fileCount, 0)
        XCTAssertEqual(snapshot.visitedFileCount, 0)
        XCTAssertFalse(snapshot.isPartial)
    }

    func testUnreadableDescendantsProduceBoundedIssuesAndPartialResults() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Permissions cannot be tested as root") }
        var restricted: [URL] = []
        defer {
            for directory in restricted { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        }
        for index in 0..<5 {
            let file = try write("restricted-\(index)/secret.bin", count: 32)
            let directory = file.deletingLastPathComponent()
            restricted.append(directory)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        }
        try write("accessible.bin", count: 71)
        let snapshot = try await DiskScanner(maxIssueCount: 2).scan(url: fixtureURL) { _ in }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.issues.count, 2)
        XCTAssertEqual(snapshot.root.logicalSize, 71)
        XCTAssertEqual(snapshot.root.fileCount, 1)
        assertConsistent(snapshot)
    }

    func testHiddenFilesAreIncluded() async throws {
        let file = try write(".config/.cache/payload.bin", count: 131)
        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }
        XCTAssertEqual(snapshot.root.logicalSize, 131)
        XCTAssertNotNil(snapshot.nodes[file.path])
    }

    func testSparseFilesReportLogicalAndAllocatedSizesSeparately() async throws {
        let file = try write("sparse.bin", count: 0)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 16 * 1024 * 1024)
        try handle.close()
        var info = stat()
        XCTAssertEqual(file.withUnsafeFileSystemRepresentation { Darwin.lstat($0!, &info) }, 0)
        let snapshot = try await DiskScanner().scan(url: fixtureURL) { _ in }
        XCTAssertEqual(snapshot.root.logicalSize, 16 * 1024 * 1024)
        XCTAssertEqual(snapshot.root.allocatedSize, Int64(info.st_blocks) * 512)
        XCTAssertLessThan(snapshot.root.allocatedSize, snapshot.root.logicalSize)
    }

    func testSingleFileCanBeScanned() async throws {
        let file = try write("single.bin", count: 123)
        let snapshot = try await DiskScanner().scan(url: file) { _ in }
        XCTAssertEqual(snapshot.nodes.count, 1)
        XCTAssertEqual(snapshot.root.logicalSize, 123)
        XCTAssertEqual(snapshot.visitedFileCount, 1)
        XCTAssertFalse(snapshot.root.isDirectory)
    }

    func testMissingRootThrowsInsteadOfShowingSuccessfulEmptyScan() async throws {
        do {
            _ = try await DiskScanner().scan(url: fixtureURL.appendingPathComponent("missing")) { _ in }
            XCTFail("A missing root must fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
        }
    }

    func testAlreadyCancelledTaskNeverStartsScanning() async throws {
        let url = fixtureURL!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DiskScanner().scan(url: url) { _ in }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancellationPropagatesToBackgroundWorker() async throws {
        try write("file.bin", count: 32)
        let reachedProgress = DispatchSemaphore(value: 0)
        let releaseProgress = DispatchSemaphore(value: 0)
        let url = fixtureURL!
        let task = Task {
            try await DiskScanner().scan(url: url) { value in
                if value.itemCount == 1 {
                    reachedProgress.signal()
                    releaseProgress.wait()
                }
            }
        }
        let reached: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: reachedProgress.wait(timeout: .now() + 5))
            }
        }
        XCTAssertEqual(reached, .success)
        task.cancel()
        releaseProgress.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation from the scanning worker")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testDemoIsExplicitlySyntheticAndInternallyConsistent() {
        let snapshot = DiskSnapshot.demo
        XCTAssertTrue(snapshot.isDemo)
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertGreaterThan(snapshot.nodes.count, 90)
        XCTAssertGreaterThan(snapshot.root.logicalSize, 200_000_000_000)
        XCTAssertEqual(snapshot.root.fileCount, snapshot.visitedFileCount)
        XCTAssertEqual(snapshot.categoryTotals.values.reduce(0, +), snapshot.root.logicalSize)
        XCTAssertTrue(FileCategory.allCases.allSatisfy { snapshot.categoryTotals[$0, default: 0] > 0 })
        assertConsistent(snapshot)
    }

    private func assertConsistent(_ snapshot: DiskSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        for node in snapshot.nodes.values where node.isDirectory {
            let children = node.children.compactMap { snapshot.nodes[$0] }
            XCTAssertEqual(children.count, node.children.count, file: file, line: line)
            XCTAssertTrue(children.allSatisfy { $0.parentID == node.id }, file: file, line: line)
            XCTAssertEqual(node.logicalSize, children.reduce(0) { $0 + $1.logicalSize }, file: file, line: line)
            XCTAssertEqual(node.allocatedSize, children.reduce(0) { $0 + $1.allocatedSize }, file: file, line: line)
            XCTAssertEqual(node.fileCount, children.reduce(0) { $0 + $1.fileCount }, file: file, line: line)
        }
    }
}
