import XCTest
import Foundation
@testable import AsterCore

final class DiskSearchTests: XCTestCase {
    func testNameAndParentPathMatchingIgnoreCaseAndOuterWhitespace() {
        let snapshot = fixture()
        XCTAssertEqual(DiskSearch.find(in: snapshot, query: "  REPORT.PDF  ").totalCount, 2)
        XCTAssertEqual(DiskSearch.find(in: snapshot, query: "pRoJeCtS").files.map(\.id), ["/fixture/Projects/report.pdf"])
        XCTAssertEqual(DiskSearch.find(in: snapshot, query: "CAFÉ").files.map(\.name), ["Café.mov"])
        XCTAssertEqual(DiskSearch.find(in: snapshot, query: "cafe").files.map(\.name), ["Café.mov"])
        XCTAssertEqual(DiskSearch.find(in: snapshot, query: "does-not-exist").totalCount, 0)
    }

    func testSizeThresholdIsInclusiveAndUsesLogicalBytes() {
        let snapshot = fixture()
        let result = DiskSearch.find(in: snapshot, minimumSize: 120)
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertEqual(result.totalBytes, 1564)
        XCTAssertTrue(result.files.allSatisfy { $0.logicalSize >= 120 })
        XCTAssertEqual(DiskSearch.find(in: snapshot, minimumSize: 1024).files.map(\.name), ["huge.zip"])
        XCTAssertEqual(DiskSearch.find(in: snapshot, minimumSize: 1025).totalCount, 0)
    }

    func testCategoryCanCombineWithQueryAndSize() {
        let result = DiskSearch.find(in: fixture(), query: "report", category: .documents, minimumSize: 120)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.totalBytes, 240)
        XCTAssertEqual(DiskSearch.find(in: fixture(), query: "report", category: .archives).totalCount, 0)
    }

    func testDirectoriesAndSymlinksNeverAppearEvenWhenLarge() {
        let result = DiskSearch.find(in: fixture())
        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.totalBytes, 1564)
        XCTAssertFalse(result.files.contains { $0.isDirectory || $0.isSymbolicLink })
        XCTAssertEqual(DiskSearch.find(in: fixture(), query: "shortcut").totalCount, 0)
    }

    func testLimitOnlyRestrictsRowsNotMatchingCountOrBytes() {
        let result = DiskSearch.find(in: fixture(), limit: 2)
        XCTAssertEqual(result.files.map(\.name), ["huge.zip", "Café.mov"])
        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.totalBytes, 1564)
        let zero = DiskSearch.find(in: fixture(), limit: 0)
        XCTAssertTrue(zero.files.isEmpty)
        XCTAssertEqual(zero.totalCount, 5)
        XCTAssertEqual(DiskSearch.find(in: fixture(), limit: -1).files.count, 0)
    }

    func testEqualSizesAndNamesUseStablePathTieBreaks() {
        let expected = ["/fixture/Downloads/report.pdf", "/fixture/Projects/report.pdf"]
        XCTAssertEqual(DiskSearch.find(in: fixture(), query: "report", sort: .size).files.map(\.id), expected)
        XCTAssertEqual(DiskSearch.find(in: fixture(), query: "report", sort: .name).files.map(\.id), expected)
    }

    func testModifiedSortPlacesNewestFirstAndBreaksUnknownDateTiesByPath() {
        let snapshot = fixture()
        XCTAssertEqual(DiskSearch.find(in: snapshot, sort: .modified).files.map(\.name), ["report.pdf", "report.pdf", "Café.mov", "huge.zip", "zero.bin"])
        var nodes = snapshot.nodes
        nodes["/fixture/zero.bin"]?.modificationDate = .distantPast
        let altered = DiskSnapshot(rootID: snapshot.rootID, nodes: nodes, startedAt: snapshot.startedAt, finishedAt: snapshot.finishedAt, visitedFileCount: snapshot.visitedFileCount)
        XCTAssertEqual(Array(DiskSearch.find(in: altered, sort: .modified).files.suffix(2)).map(\.id), ["/fixture/Archive/huge.zip", "/fixture/zero.bin"])
    }

    private func fixture() -> DiskSnapshot {
        func file(_ path: String, size: Int64, category: FileCategory, date: TimeInterval?) -> DiskNode {
            let url = URL(fileURLWithPath: path)
            return DiskNode(id: path, url: url, name: url.lastPathComponent, isDirectory: false, logicalSize: size, allocatedSize: 4096, fileCount: 1, parentID: url.deletingLastPathComponent().path, modificationDate: date.map { Date(timeIntervalSince1970: $0) }, category: category)
        }
        let files = [
            file("/fixture/Projects/report.pdf", size: 120, category: .documents, date: 300),
            file("/fixture/Downloads/report.pdf", size: 120, category: .documents, date: 200),
            file("/fixture/Archive/huge.zip", size: 1024, category: .archives, date: nil),
            file("/fixture/Movies/Café.mov", size: 300, category: .media, date: 100),
            file("/fixture/zero.bin", size: 0, category: .other, date: nil)
        ]
        var nodes = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        nodes["/fixture"] = DiskNode(id: "/fixture", url: URL(fileURLWithPath: "/fixture"), name: "fixture", isDirectory: true, logicalSize: 1564, allocatedSize: 20_480, fileCount: 5, children: files.map(\.id), category: .other)
        nodes["/fixture/shortcut"] = DiskNode(id: "/fixture/shortcut", url: URL(fileURLWithPath: "/fixture/shortcut"), name: "shortcut", isDirectory: false, isSymbolicLink: true, logicalSize: 9999, allocatedSize: 4096, fileCount: 0, parentID: "/fixture", category: .other)
        return DiskSnapshot(rootID: "/fixture", nodes: nodes, startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 1), visitedFileCount: 5)
    }
}
