import XCTest
import Foundation
import Darwin
@testable import AsterCore

final class AppInventoryTests: XCTestCase {
    private var fixture: URL!
    private var applications: URL!
    private var library: URL!

    override func setUpWithError() throws {
        // Foundation may rewrite /private/var to its /var symlink alias. Keep
        // fixtures in an explicit physical path to test strict link handling.
        fixture = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("AsterInventoryTests-\(UUID().uuidString)", isDirectory: true)
        applications = fixture.appendingPathComponent("Applications", isDirectory: true)
        library = fixture.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try FileManager.default.removeItem(at: fixture) }
    }

    @discardableResult
    private func app(_ path: String, identifier: String?, name: String? = nil) throws -> URL {
        let url = applications.appendingPathComponent(path, isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [:]
        if let identifier { info["CFBundleIdentifier"] = identifier }
        if let name { info["CFBundleDisplayName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    @discardableResult
    private func dataPath(_ path: String, isFile: Bool = false) throws -> URL {
        let url = library.appendingPathComponent(path, isDirectory: !isFile)
        if isFile {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func scan() async throws -> AppInventoryResult {
        try await AppInventoryScanner.scan(applicationRoots: [applications], userLibrary: library)
    }

    func testFindsAppInCustomRootAndUsesOnlyExactIdentifierPaths() async throws {
        let bundle = try app("Tools/Editor.app", identifier: "com.acme.editor", name: "Acme Editor")
        let expected = try dataPath("Caches/com.acme.editor")
        try dataPath("Caches/com.acme.editor-pro")
        try dataPath("Application Support/Acme Editor")
        try dataPath("Application Support/com.acme.editor")
        try dataPath("Preferences/com.acme.editor.plist", isFile: true)
        try dataPath("Preferences/com.acme.editor.plist.backup", isFile: true)
        let result = try await scan()

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.apps.count, 1)
        let found = try XCTUnwrap(result.apps.first)
        XCTAssertEqual(found.id, bundle.path)
        XCTAssertEqual(found.name, "Acme Editor")
        XCTAssertEqual(found.relatedFiles.count, 3)
        XCTAssertTrue(found.relatedFiles.contains { $0.url.path == expected.path })
        XCTAssertFalse(found.relatedFiles.contains { $0.url.lastPathComponent == "com.acme.editor-pro" })
        XCTAssertFalse(found.relatedFiles.contains { $0.url.lastPathComponent == "Acme Editor" })
        XCTAssertTrue(found.relatedFiles.allSatisfy { $0.ownerBundleIdentifier == "com.acme.editor" })
        XCTAssertFalse(result.isDemo)
    }

    func testFindsEverySupportedLocationAndExcludesPrivilegedOrSharedLocations() async throws {
        try app("Editor.app", identifier: "com.acme.editor")
        for path in ["Caches", "Application Support", "Containers", "Logs", "WebKit", "HTTPStorages"] {
            try dataPath("\(path)/com.acme.editor")
        }
        try dataPath("Preferences/com.acme.editor.plist", isFile: true)
        try dataPath("Saved Application State/com.acme.editor.savedState")
        try dataPath("Group Containers/com.acme.editor")
        try dataPath("LaunchAgents/com.acme.editor.plist", isFile: true)
        try dataPath("LaunchDaemons/com.acme.editor.plist", isFile: true)
        let result = try await scan()

        let found = try XCTUnwrap(result.apps.first)
        XCTAssertEqual(found.relatedFiles.count, 8)
        XCTAssertEqual(Set(found.relatedFiles.map(\.kind)), Set(AppRelatedKind.allCases))
        XCTAssertTrue(found.relatedFiles.allSatisfy { !$0.caution.isEmpty })
        let support = try XCTUnwrap(found.relatedFiles.first { $0.kind == .applicationSupport })
        XCTAssertTrue(support.caution.contains("databases"))
        XCTAssertFalse(found.relatedFiles.contains { $0.url.path.contains("Group Containers") })
        XCTAssertFalse(found.relatedFiles.contains { $0.url.path.contains("LaunchAgents") })
    }

    func testMissingAndInvalidIdentifiersMakeDiscoveryIncompleteAndSuppressLeftovers() async throws {
        try app("Missing.app", identifier: nil)
        try app("Invalid.app", identifier: "../elsewhere")
        try app("Generic.app", identifier: "editor")
        try app("Valid.app", identifier: "com.acme.valid")
        try dataPath("Caches/com.acme.removed")
        let result = try await scan()

        XCTAssertEqual(result.apps.map(\.bundleIdentifier), ["com.acme.valid"])
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("identifier is missing or invalid") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Possible leftovers are hidden") })
    }

    func testProtectedAppleAppsAndNestedHelpersAreNotOffered() async throws {
        try app("Apple.app", identifier: "com.apple.Example")
        try app("Host.app", identifier: "com.acme.host")
        try app("Host.app/Contents/Helpers/Helper.app", identifier: "com.acme.host.helper")
        try dataPath("Caches/com.apple.Example")
        try dataPath("Caches/com.acme.host.helper")
        try dataPath("Caches/com.acme.host.helper.extension")
        let result = try await scan()

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.apps.map(\.bundleIdentifier), ["com.acme.host"])
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertTrue(try XCTUnwrap(result.apps.first).relatedFiles.isEmpty)
    }

    func testPossibleLeftoversRemainUncertainAndIgnoreGenericHiddenAndApplePaths() async throws {
        try app("Active.app", identifier: "com.acme.active")
        try dataPath("Caches/com.acme.removed")
        try dataPath("Preferences/com.acme.removed.plist", isFile: true)
        try dataPath("Caches/com.acme.active.helper")
        try dataPath("Caches/com.acme.active2")
        try dataPath("Caches/COM.ACME.ACTIVE.plugin")
        try dataPath("Caches/Generic Cache")
        try dataPath("Caches/foo.bar")
        try dataPath("Caches/.com.acme.hidden")
        try dataPath("Caches/com.apple.oldapp")
        try dataPath("Caches/group.com.acme.shared")
        try dataPath("Group Containers/com.acme.group")
        let result = try await scan()

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.leftovers.map(\.bundleIdentifier), ["com.acme.active2", "com.acme.removed"])
        let removed = try XCTUnwrap(result.leftovers.first { $0.bundleIdentifier == "com.acme.removed" })
        XCTAssertEqual(removed.files.count, 2)
        XCTAssertEqual(removed.title, "Possible leftover")
        XCTAssertTrue(removed.caution.contains("unverified"))
        XCTAssertTrue(removed.caution.contains("outside the scanned folders"))
        XCTAssertTrue(removed.files.allSatisfy { $0.reason.contains("does not prove") })
    }

    func testDuplicateAppCopiesRemainSeparateAndKeepTheirExactIdentity() async throws {
        let first = try app("Editor.app", identifier: "com.acme.editor")
        let second = try app("Archive/Editor.app", identifier: "com.acme.editor")
        try dataPath("Caches/com.acme.editor")
        let result = try await scan()

        XCTAssertEqual(result.apps.count, 2)
        XCTAssertEqual(Set(result.apps.map(\.id)), [first.path, second.path])
        XCTAssertTrue(result.apps.allSatisfy { $0.relatedFiles.count == 1 })
        XCTAssertTrue(result.leftovers.isEmpty)
    }

    func testSymbolicLinkedAppsAndRelatedDataAreExcludedAndReported() async throws {
        let real = try app("Real.app", identifier: "com.acme.real")
        let realCache = try dataPath("Caches/com.acme.real")
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Alias.app"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Caches/com.acme.alias"), withDestinationURL: realCache)
        let result = try await scan()

        XCTAssertEqual(result.apps.count, 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Symbolic link was excluded") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Symbolic-link related data was excluded") })
    }

    func testProtectedSystemAliasesAndRegularDocumentLinksDoNotBlockDiscovery() async throws {
        try app("Real.app", identifier: "com.acme.real")
        let document = fixture.appendingPathComponent("Documentation.html")
        try Data("fixture documentation".utf8).write(to: document)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Documentation.html"), withDestinationURL: document)
        // The target is inspected only as metadata. The scanner must never
        // enumerate the actual system directory through this fixture alias.
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("System.app"), withDestinationURL: URL(fileURLWithPath: "/System/Library", isDirectory: true))
        try dataPath("Caches/com.acme.removed")
        let result = try await scan()

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.apps.map(\.bundleIdentifier), ["com.acme.real"])
        XCTAssertEqual(result.leftovers.map(\.bundleIdentifier), ["com.acme.removed"])
    }

    func testUnprotectedDirectoryAndBrokenAliasesStillBlockOrphanClaims() async throws {
        let outside = fixture.appendingPathComponent("Other Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Other Applications"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Broken.app"), withDestinationURL: fixture.appendingPathComponent("Absent.app"))
        try dataPath("Caches/com.acme.removed")
        let result = try await scan()

        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertEqual(result.warnings.filter { $0.contains("Symbolic link was excluded") }.count, 2)
    }

    func testUnreadableApplicationRootSuppressesLeftovers() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission fixture requires a non-root user") }
        let restricted = applications.appendingPathComponent("Restricted")
        try FileManager.default.createDirectory(at: restricted, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path) }
        try dataPath("Caches/com.acme.maybe")
        let result = try await scan()

        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Could not read application folder") })
    }

    func testUnreadableLibraryFolderKeepsKnownAppsButSuppressesLeftovers() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission fixture requires a non-root user") }
        try app("Real.app", identifier: "com.acme.real")
        try dataPath("Caches/com.acme.real")
        try dataPath("Caches/com.acme.maybe")
        let restricted = try dataPath("Application Support")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path) }
        let result = try await scan()

        XCTAssertEqual(result.apps.count, 1)
        XCTAssertEqual(result.apps.first?.relatedFiles.count, 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.leftovers.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Could not read related-data folder") })
    }

    func testMissingChosenRootOrLibraryCannotProduceOrphanClaims() async throws {
        try dataPath("Caches/com.acme.maybe")
        let missing = fixture.appendingPathComponent("Missing")
        let missingRoot = try await AppInventoryScanner.scan(applicationRoots: [missing], userLibrary: library)
        XCTAssertFalse(missingRoot.isComplete)
        XCTAssertTrue(missingRoot.leftovers.isEmpty)
        XCTAssertFalse(missingRoot.warnings.isEmpty)

        let missingLibrary = try await AppInventoryScanner.scan(applicationRoots: [applications], userLibrary: missing)
        XCTAssertFalse(missingLibrary.isComplete)
        XCTAssertTrue(missingLibrary.leftovers.isEmpty)
        XCTAssertTrue(missingLibrary.warnings.contains { $0.contains("user Library") })
    }

    func testAlreadyCancelledDiscoveryThrows() async throws {
        let roots = [applications!]
        let userLibrary = library!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AppInventoryScanner.scan(applicationRoots: roots, userLibrary: userLibrary)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation is surfaced rather than showing a successful empty result.
        }
    }

    func testNumericIdentifierComponentsRemainValid() async throws {
        try app("Passwords.app", identifier: "com.1password.1password")
        try dataPath("Caches/com.1password.1password")
        let result = try await scan()
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.apps.first?.bundleIdentifier, "com.1password.1password")
        XCTAssertEqual(result.apps.first?.relatedFiles.count, 1)
    }

    func testRootAncestorSymlinksAreRejectedForApplicationsAndLibrary() async throws {
        try app("Real.app", identifier: "com.acme.real")
        try dataPath("Caches/com.acme.maybe")
        let alias = fixture.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture)
        let appAlias = try await AppInventoryScanner.scan(applicationRoots: [alias.appendingPathComponent("Applications")], userLibrary: library)
        XCTAssertFalse(appAlias.isComplete)
        XCTAssertTrue(appAlias.apps.isEmpty)
        XCTAssertTrue(appAlias.leftovers.isEmpty)
        XCTAssertTrue(appAlias.warnings.contains { $0.contains("Symbolic-link application location") })

        let libraryAlias = try await AppInventoryScanner.scan(applicationRoots: [applications], userLibrary: alias.appendingPathComponent("Library"))
        XCTAssertFalse(libraryAlias.isComplete)
        XCTAssertEqual(libraryAlias.apps.count, 1)
        XCTAssertTrue(try XCTUnwrap(libraryAlias.apps.first).relatedFiles.isEmpty)
        XCTAssertTrue(libraryAlias.leftovers.isEmpty)
        XCTAssertTrue(libraryAlias.warnings.contains { $0.contains("Symbolic-link user Library location") })
    }

    func testDemoIsExplicitAndOnlyUsesSyntheticPaths() {
        let demo = AppInventoryResult.demo
        XCTAssertTrue(demo.isDemo)
        XCTAssertFalse(demo.apps.isEmpty)
        XCTAssertFalse(demo.leftovers.isEmpty)
        XCTAssertTrue(demo.apps.allSatisfy { $0.bundleURL.path.hasPrefix("/Aster Demo/") })
        XCTAssertTrue(demo.apps.flatMap(\.relatedFiles).allSatisfy { $0.url.path.hasPrefix("/Aster Demo/") })
    }
}
