import XCTest
import Foundation
import Darwin
@testable import AsterCore

final class TrashServiceTests: XCTestCase {
    private var root: URL!
    private var mover: FixtureTrashMover!

    override func setUpWithError() throws {
        // Use the physical spelling: /tmp and /var are symlink aliases on macOS.
        root = URL(fileURLWithPath: "/private/tmp/aster-trash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        mover = try FixtureTrashMover(destination: root.appendingPathComponent("test-trash"))
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func service(maxItems: Int = 100_000) -> TrashService {
        let fake = mover!
        return TrashService(policy: TrashPolicy(allowedRoots: [root], maxItems: maxItems), mover: { try fake.move($0) })
    }

    @discardableResult
    private func write(_ name: String, _ content: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func makeApp(_ name: String, identifier: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    func testPreviewMeasuresWithoutMovingAndConfirmedSubsetMovesOnlyOnce() async throws {
        let first = try write("first.txt", "hello")
        let second = try write("second.txt", "world!")
        let service = service()
        let preview = await service.prepare(urls: [first, second])
        XCTAssertEqual(preview.items.map(\.logicalSize), [5, 6])
        XCTAssertTrue(preview.items.allSatisfy(\.canMove))
        XCTAssertTrue(mover.calls.isEmpty)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [first.path])
        XCTAssertEqual(report.results.map(\.status), [.moved, .skipped])
        XCTAssertNotNil(report.results[0].trashURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let reused = await service.moveToTrash(preview: preview, confirmedIDs: [second.path])
        XCTAssertTrue(reused.previewAlreadyUsed)
        XCTAssertTrue(reused.results.allSatisfy { $0.status == .skipped })
        XCTAssertEqual(mover.calls, [first.path])
    }

    func testNestedAndRepeatedSelectionsAreDeduplicated() async throws {
        let child = try write("folder/nested/child.txt", "abc")
        let folder = root.appendingPathComponent("folder")
        let service = service()
        let preview = await service.prepare(urls: [child, folder, child])
        XCTAssertEqual(preview.items.count, 1)
        XCTAssertEqual(preview.items[0].id, folder.path)
        XCTAssertEqual(preview.items[0].logicalSize, 3)
        XCTAssertEqual(preview.items[0].fileCount, 1)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [folder.path])
        XCTAssertEqual(report.results.first?.status, .moved)
        XCTAssertEqual(mover.calls.count, 1)
    }

    func testChangedFileIsSkippedAndRetained() async throws {
        let file = try write("changing.txt", "before")
        let service = service()
        let preview = await service.prepare(urls: [file])
        try Data("after!".utf8).write(to: file)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [file.path])
        XCTAssertEqual(report.results.first?.status, .skipped)
        XCTAssertTrue(report.results[0].message.contains("changed"))
        XCTAssertTrue(mover.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testChangedNestedContentsRequireNewPreview() async throws {
        let file = try write("folder/deeper/file.txt", "before")
        let folder = root.appendingPathComponent("folder")
        let service = service()
        let preview = await service.prepare(urls: [folder])
        try Data("after!".utf8).write(to: file)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [folder.path])
        XCTAssertEqual(report.results.first?.status, .skipped)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testNewDirectoryEntryRequiresNewPreview() async throws {
        try write("folder/first.txt")
        let folder = root.appendingPathComponent("folder")
        let service = service()
        let preview = await service.prepare(urls: [folder])
        try write("folder/new.txt")
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [folder.path])
        XCTAssertEqual(report.results.first?.status, .skipped)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testSelectedSymlinksAndSymlinkedParentsAreBlocked() async throws {
        let target = try write("original/file.txt")
        let fileLink = root.appendingPathComponent("file-link")
        let directoryLink = root.appendingPathComponent("directory-link")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: target.deletingLastPathComponent())
        let service = service()
        let preview = await service.prepare(urls: [fileLink, directoryLink.appendingPathComponent("file.txt")])
        XCTAssertEqual(preview.items.count, 2)
        XCTAssertTrue(preview.items.allSatisfy { !$0.canMove })
        let report = await service.moveToTrash(preview: preview, confirmedIDs: Set(preview.items.map(\.id)))
        XCTAssertTrue(report.results.allSatisfy { $0.status == .skipped })
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testNestedSymlinkMovesOnlyTheLinkAndKeepsTarget() async throws {
        let target = try write("outside.txt", "keep")
        try write("folder/inside.txt", "move")
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: target)
        let service = service()
        let preview = await service.prepare(urls: [folder])
        XCTAssertTrue(preview.items[0].canMove)
        XCTAssertEqual(preview.items[0].logicalSize, 4)
        XCTAssertTrue(preview.items[0].warnings.contains { $0.contains("symbolic link") })
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [folder.path])
        XCTAssertEqual(report.results[0].status, .moved)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
    }

    func testProtectedDescendantBlocksParentAndNewProtectionBlocksExecution() async throws {
        let file = try write("folder/protected.txt")
        let folder = root.appendingPathComponent("folder")
        let service = service()
        let blocked = await service.prepare(urls: [folder], protectedURLs: [file])
        XCTAssertFalse(blocked.items[0].canMove)
        let preview = await service.prepare(urls: [file])
        XCTAssertTrue(preview.items[0].canMove)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [file.path], protectedURLs: [file])
        XCTAssertEqual(report.results[0].status, .skipped)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testSystemTrashAndNonLocalLocationsAreBlocked() async throws {
        let trashFile = try write(".Trash/keep.txt")
        let service = service()
        for url in [URL(fileURLWithPath: "/"), trashFile, URL(string: "https://example.com/file")!, URL(string: "file://example.com/private/tmp/file")!] {
            let preview = await service.prepare(urls: [url])
            XCTAssertFalse(preview.items[0].canMove, url.absoluteString)
        }
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testAppleAppsAndApplicationInternalsAreBlocked() async throws {
        let apple = try makeApp("Apple.app", identifier: "com.apple.fixture")
        let thirdParty = try makeApp("ThirdParty.app", identifier: "example.fixture.thirdparty")
        let service = service()
        let blocked = await service.prepare(urls: [apple, thirdParty.appendingPathComponent("Contents/Info.plist")])
        XCTAssertTrue(blocked.items.allSatisfy { !$0.canMove })
        let preview = await service.prepare(urls: [thirdParty])
        XCTAssertTrue(preview.items[0].canMove)
        let report = await service.moveToTrash(preview: preview, confirmedIDs: [thirdParty.path])
        XCTAssertEqual(report.results[0].status, .moved)
    }

    func testLibraryRootsStayProtectedWhileExactThirdPartyContainersCanBeReviewed() async throws {
        let home = root.appendingPathComponent("fixture-home")
        let thirdPartyFile = try write("fixture-home/Library/Containers/com.example.app/Data/file.txt")
        try write("fixture-home/Library/Containers/com.apple.fixture/Data/file.txt")
        try write("fixture-home/Library/Containers/generic/Data/file.txt")
        try write("fixture-home/Library/Group Containers/com.example.shared/file.txt")
        for name in ["Logs", "WebKit", "HTTPStorages", "Saved Application State"] { try write("fixture-home/Library/\(name)/com.example.app/file.txt") }
        let fake = mover!
        let service = TrashService(policy: TrashPolicy(allowedRoots: [root], homeDirectory: home), mover: { try fake.move($0) })
        let library = home.appendingPathComponent("Library")
        let blockedURLs = [home, library, library.appendingPathComponent("Containers"), library.appendingPathComponent("Containers/com.apple.fixture"), library.appendingPathComponent("Containers/generic"), library.appendingPathComponent("Group Containers/com.example.shared"), thirdPartyFile] + ["Logs", "WebKit", "HTTPStorages", "Saved Application State"].map { library.appendingPathComponent($0) }
        // Prepare individually, since parent selection intentionally deduplicates descendants.
        for url in blockedURLs {
            let preview = await service.prepare(urls: [url])
            XCTAssertFalse(preview.items[0].canMove, url.path)
        }
        let container = library.appendingPathComponent("Containers/com.example.app")
        let allowed = await service.prepare(urls: [container])
        XCTAssertTrue(allowed.items[0].canMove)
        let report = await service.moveToTrash(preview: allowed, confirmedIDs: [container.path])
        XCTAssertEqual(report.results[0].status, .moved)
    }

    func testItemLimitAndUnreadableFolderFailClosed() async throws {
        try write("folder/one.txt")
        try write("folder/two.txt")
        let folder = root.appendingPathComponent("folder")
        let capped = await service(maxItems: 1).prepare(urls: [folder])
        XCTAssertFalse(capped.items[0].canMove)
        guard geteuid() != 0 else { throw XCTSkip("Permissions cannot be tested as root") }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let unreadable = await service().prepare(urls: [folder])
        XCTAssertFalse(unreadable.items[0].canMove)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testMoverFailureHasNoDeleteFallbackAndOtherItemsContinue() async throws {
        let first = try write("fail.txt")
        let second = try write("succeed.txt")
        mover.failNames = ["fail.txt"]
        let service = service()
        let preview = await service.prepare(urls: [first, second])
        let report = await service.moveToTrash(preview: preview, confirmedIDs: Set(preview.items.map(\.id)))
        XCTAssertEqual(report.results.map(\.status), [.failed, .moved])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testUnknownConfirmationAndForeignPreviewCannotMoveAnything() async throws {
        let file = try write("keep.txt")
        let service = service()
        let preview = await service.prepare(urls: [file])
        let invalid = await service.moveToTrash(preview: preview, confirmedIDs: [file.path, "/not-in-preview"])
        XCTAssertTrue(invalid.results.allSatisfy { $0.status == .skipped })
        let foreign = await self.service().moveToTrash(preview: preview, confirmedIDs: [file.path])
        XCTAssertTrue(foreign.results.allSatisfy { $0.status == .skipped })
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testCancellationPreservesCompletedMoveAndStopsAdditionalMoves() async throws {
        let first = try write("first.txt")
        let second = try write("second.txt")
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        mover.gate = (reached, release)
        let service = service()
        let preview = await service.prepare(urls: [first, second])
        let task = Task { await service.moveToTrash(preview: preview, confirmedIDs: Set(preview.items.map(\.id))) }
        let started: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: reached.wait(timeout: .now() + 5)) }
        }
        XCTAssertEqual(started, .success)
        task.cancel()
        release.signal()
        let report = await task.value
        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.results.map(\.status), [.moved, .skipped])
        XCTAssertEqual(mover.calls, [first.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testDependencyFailureKeepsRelatedDataAndSuccessOrdersPrerequisiteFirst() async throws {
        let app = try makeApp("Fail.app", identifier: "example.fixture.fail")
        let data = try write("related.data")
        mover.failNames = ["Fail.app"]
        let service = service()
        let preview = await service.prepare(urls: [data, app])
        let report = await service.moveToTrash(preview: preview, confirmedIDs: Set(preview.items.map(\.id)), dependencies: [data.path: app.path])
        XCTAssertEqual(report.results.map(\.status), [.failed, .skipped])
        XCTAssertEqual(mover.calls, [app.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path))
        mover.failNames = []
        let fresh = await service.prepare(urls: [data, app])
        let success = await service.moveToTrash(preview: fresh, confirmedIDs: Set(fresh.items.map(\.id)), dependencies: [data.path: app.path])
        XCTAssertEqual(success.results.map(\.id), [app.path, data.path])
        XCTAssertTrue(success.results.allSatisfy { $0.status == .moved })
    }

    func testDistinctPreviewsCannotMoveConcurrentlyAndRejectedPreviewCanBeRetried() async throws {
        let first = try write("first.txt")
        let second = try write("second.txt")
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        mover.gate = (reached, release)
        let service = service()
        let firstPreview = await service.prepare(urls: [first])
        let secondPreview = await service.prepare(urls: [second])
        let firstTask = Task { await service.moveToTrash(preview: firstPreview, confirmedIDs: [first.path]) }
        let started: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: reached.wait(timeout: .now() + 5)) }
        }
        XCTAssertEqual(started, .success)
        let overlapping = await service.moveToTrash(preview: secondPreview, confirmedIDs: [second.path])
        XCTAssertEqual(overlapping.results[0].status, .skipped)
        XCTAssertTrue(overlapping.results[0].message.contains("in progress"))
        XCTAssertFalse(overlapping.previewAlreadyUsed)
        XCTAssertEqual(mover.calls, [first.path])
        release.signal()
        let finished = await firstTask.value
        XCTAssertEqual(finished.results[0].status, .moved)
        let retry = await service.moveToTrash(preview: secondPreview, confirmedIDs: [second.path])
        XCTAssertEqual(retry.results[0].status, .moved)
        XCTAssertEqual(mover.calls, [first.path, second.path])
    }

    func testMissingUnconfirmedAndCyclicDependenciesCannotMoveRelatedItems() async throws {
        let first = try write("first.txt")
        let second = try write("second.txt")
        let service = service()
        for dependency in ["/missing", second.path] {
            let preview = await service.prepare(urls: [first, second])
            let report = await service.moveToTrash(preview: preview, confirmedIDs: [first.path], dependencies: [first.path: dependency])
            XCTAssertTrue(report.results.allSatisfy { $0.status == .skipped })
        }
        let preview = await service.prepare(urls: [first, second])
        let cycle = await service.moveToTrash(preview: preview, confirmedIDs: [first.path, second.path], dependencies: [first.path: second.path, second.path: first.path])
        XCTAssertTrue(cycle.results.allSatisfy { $0.status == .skipped })
        XCTAssertTrue(mover.calls.isEmpty)
    }
}

/// Only this test fixture mover is exercised. It never uses the user's Trash.
private final class FixtureTrashMover: @unchecked Sendable {
    let destination: URL
    var failNames = Set<String>()
    var gate: (DispatchSemaphore, DispatchSemaphore)?
    private let lock = NSLock()
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }

    init(destination: URL) throws {
        self.destination = destination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func move(_ source: URL) throws -> URL? {
        let first = lock.withLock {
            recorded.append(source.path)
            return recorded.count == 1
        }
        if failNames.contains(source.lastPathComponent) { throw NSError(domain: "FixtureTrashMover", code: 1) }
        let target = destination.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: target)
        if first, let gate {
            gate.0.signal()
            gate.1.wait()
        }
        return target
    }
}
