import Foundation

public enum DeveloperCacheCleanupPolicy: String, Sendable {
    /// Eligible for an explicit review; this does not assert the cache is unused.
    case reviewAndTrash
    /// Show measured metadata, but use the vendor's cleanup workflow.
    case vendorManaged
}

public struct DeveloperCacheLocation: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let relativeHomePath: String
    public let note: String
    public let cleanupPolicy: DeveloperCacheCleanupPolicy
    public let documentationURL: URL
}

/// Documented default locations verified against vendor documentation on
/// 2026-10-19. These descriptors are not scan results: callers must check actual
/// existence, access, symlinks and sizes before showing an entry. Tool-specific
/// environment/configuration overrides are intentionally not guessed.
///
/// The regular ~/Library/Caches discovery already covers default locations used
/// by tools such as Homebrew, pip, Go and Yarn; do not count those folders twice.
public enum DeveloperCacheLocations {
    public static let all: [DeveloperCacheLocation] = [
        DeveloperCacheLocation(
            id: "npm-package-cache",
            title: "npm package cache",
            relativeHomePath: ".npm/_cacache",
            note: "Downloaded npm package data. Stop npm tasks before cleanup; subsequent installs may need to download packages again. This location can be customized in npm.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://docs.npmjs.com/cli/cache/")!
        ),
        DeveloperCacheLocation(
            id: "gradle-caches",
            title: "Gradle caches",
            relativeHomePath: ".gradle/caches",
            note: "Build caches and downloaded dependencies. Stop Gradle builds and daemons before cleanup. Later builds may need downloads, and offline builds can be affected. Gradle also provides its own cache-retention controls.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://docs.gradle.org/current/userguide/directory_layout.html")!
        ),
        DeveloperCacheLocation(
            id: "cargo-crate-cache",
            title: "Cargo crate downloads",
            relativeHomePath: ".cargo/registry/cache",
            note: "Downloaded crate archives used by Rust builds. Stop Cargo jobs before cleanup; subsequent builds may require network access to fetch dependencies again.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://doc.rust-lang.org/cargo/guide/cargo-home.html")!
        ),
        // Do not broaden these to .kube/cache: authentication plugins can store
        // access and refresh tokens in sibling directories such as oidc-login.
        DeveloperCacheLocation(
            id: "kubernetes-discovery-cache",
            title: "Kubernetes discovery cache",
            relativeHomePath: ".kube/cache/discovery",
            note: "kubectl's cached API discovery information. Stop Kubernetes client operations before cleanup; future discovery requires contacting the cluster. Configurations and authentication-token caches are excluded.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://github.com/kubernetes/cli-runtime/blob/master/pkg/genericclioptions/config_flags.go")!
        ),
        DeveloperCacheLocation(
            id: "kubernetes-http-cache",
            title: "Kubernetes HTTP cache",
            relativeHomePath: ".kube/cache/http",
            note: "kubectl's cached HTTP responses. Stop Kubernetes client operations before cleanup; future requests may need network access. Configurations and authentication-token caches are excluded.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://github.com/kubernetes/cli-runtime/blob/master/pkg/genericclioptions/config_flags.go")!
        ),
        DeveloperCacheLocation(
            id: "minikube-resource-cache",
            title: "minikube cached resources",
            relativeHomePath: ".minikube/cache",
            note: "Cached VM resources and images, including images explicitly added by the user. These can be needed for offline starts. Review them with minikube's cache commands; Aster does not move this directory to Trash.",
            cleanupPolicy: .vendorManaged,
            documentationURL: URL(string: "https://minikube.sigs.k8s.io/docs/handbook/offline/")!
        ),
        DeveloperCacheLocation(
            id: "xcode-derived-data",
            title: "Xcode Derived Data",
            relativeHomePath: "Library/Developer/Xcode/DerivedData",
            note: "Generated build and index data, plus local build and test results. Quit Xcode and build jobs before cleanup. Keep any results or artifacts you need; later builds will rebuild generated data.",
            cleanupPolicy: .reviewAndTrash,
            documentationURL: URL(string: "https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes")!
        ),
        DeveloperCacheLocation(
            id: "docker-desktop-logs",
            title: "Docker Desktop logs",
            relativeHomePath: "Library/Containers/com.docker.docker/Data/log",
            note: "Docker Desktop diagnostic logs. Review or manage them through Docker Desktop; Aster only measures this protected location. Docker disk images, containers and volumes are excluded from these cleanup suggestions.",
            cleanupPolicy: .vendorManaged,
            documentationURL: URL(string: "https://docs.docker.com/engine/daemon/logs/")!
        ),
        DeveloperCacheLocation(
            id: "uv-cache",
            title: "uv package cache",
            relativeHomePath: ".cache/uv",
            note: "uv requires its own cache-cleanup commands to coordinate with running processes. Use uv cache clean or uv cache prune after reviewing their effects; Aster does not manually move this cache to Trash.",
            cleanupPolicy: .vendorManaged,
            documentationURL: URL(string: "https://docs.astral.sh/uv/concepts/cache/")!
        )
    ]
}
