import XCTest
import Foundation
@testable import AsterCore

final class DeveloperCacheLocationsTests: XCTestCase {
    func testLocationsCannotEscapeHomeOrDoubleCountOverlappingRoots() {
        let entries = DeveloperCacheLocations.all
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        for entry in entries {
            let components = entry.relativeHomePath.split(separator: "/", omittingEmptySubsequences: false)
            XCTAssertFalse(entry.relativeHomePath.hasPrefix("/"), entry.id)
            XCTAssertFalse(components.contains { $0 == ".." || $0 == "." || $0.isEmpty }, entry.id)
            XCTAssertEqual(entry.documentationURL.scheme, "https", entry.id)
            for other in entries where entry.id != other.id {
                XCTAssertFalse(other.relativeHomePath == entry.relativeHomePath || other.relativeHomePath.hasPrefix(entry.relativeHomePath + "/"), "Overlapping descriptors: \(entry.id), \(other.id)")
            }
        }
    }

    func testCredentialsClusterStateAndDockerDisksStayOutsideEverySuggestedTree() {
        let protectedPaths = [
            ".kube/config", ".kube/cache/oidc-login/token.json", ".kube/cache/kubelogin/token.json",
            ".docker/config.json", ".docker/contexts/meta/fixture/meta.json",
            ".minikube/profiles/fixture/config.json", ".minikube/machines/fixture/disk.vmdk",
            ".cargo/credentials.toml", ".cargo/config.toml", ".cargo/bin/rust-tool",
            ".gradle/gradle.properties", "Library/Developer/Xcode/Archives/retained.xcarchive",
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        ]
        for entry in DeveloperCacheLocations.all {
            for protected in protectedPaths {
                XCTAssertFalse(protected == entry.relativeHomePath || protected.hasPrefix(entry.relativeHomePath + "/"), "\(entry.id) would include \(protected)")
            }
        }
    }

    func testVendorManagedDataCannotBecomeDirectTrashSuggestions() {
        for id in ["docker-desktop-logs", "minikube-resource-cache", "uv-cache"] {
            XCTAssertEqual(DeveloperCacheLocations.all.first { $0.id == id }?.cleanupPolicy, .vendorManaged, id)
        }
    }
}
