import Foundation
import AsterCore

extension DiskSnapshot {
    /// Synthetic test fixture, compiled only into the test target.
    static let demo: DiskSnapshot = {
        let GB: Int64 = 1_000_000_000
        let MB: Int64 = 1_000_000
        let sample: DemoEntry = .folder("Macintosh HD", .other, [
            .folder("Developer", .developer, [
                .folder("Xcode", .developer, [
                    .folder("iOS Simulators", .developer, [
                        .file("iOS 18.5.simruntime", 12 * GB + 430 * MB),
                        .file("iOS 18.2.simruntime", 11 * GB + 760 * MB),
                        .file("iOS 17.5.simruntime", 10 * GB + 260 * MB),
                        .file("watchOS 11.5.simruntime", 5 * GB + 80 * MB)
                    ]),
                    .folder("DerivedData", .developer, [
                        .file("Studio-build-cache.dat", 5 * GB + 840 * MB),
                        .file("Aster-build-cache.dat", 3 * GB + 260 * MB),
                        .file("ModuleCache.noindex", 2 * GB + 180 * MB),
                        .file("Previews-cache.dat", 890 * MB)
                    ]),
                    .folder("Archives", .developer, [
                        .file("Studio 2.4.xcarchive", 2 * GB + 620 * MB),
                        .file("Studio 2.3.xcarchive", 2 * GB + 340 * MB),
                        .file("Aster 0.1.xcarchive", 1 * GB + 160 * MB)
                    ])
                ]),
                .folder("Local models", .developer, [
                    .file("qwen3-32b-q4_k_m.gguf", 19 * GB + 870 * MB),
                    .file("llama-3.1-8b-q8_0.gguf", 8 * GB + 540 * MB),
                    .file("embedding-model.safetensors", 570 * MB)
                ]),
                .folder("Projects", .developer, [
                    .folder("studio-web", .developer, [
                        .file("node_modules.cache", 1 * GB + 420 * MB),
                        .file(".next-cache", 860 * MB),
                        .file("design-system.fig", 420 * MB),
                        .file("package-lock.json", 2 * MB)
                    ]),
                    .folder("aster-mac", .developer, [
                        .file(".build-cache", 1 * GB + 100 * MB),
                        .file("Aster.swift", 42_000),
                        .file("README.md", 18_000)
                    ])
                ])
            ]),
            .folder("Movies", .media, [
                .folder("Studio film", .media, [
                    .file("Launch film — final.mov", 14 * GB + 640 * MB),
                    .file("Interview — camera A.mov", 11 * GB + 420 * MB),
                    .file("Interview — camera B.mov", 9 * GB + 780 * MB),
                    .file("B-roll — city.mov", 8 * GB + 270 * MB),
                    .file("Launch film — web.mp4", 2 * GB + 460 * MB),
                    .file("Soundtrack.wav", 780 * MB)
                ]),
                .folder("Screen recordings", .media, [
                    .file("Product walkthrough.mov", 3 * GB + 180 * MB),
                    .file("Design review.mov", 1 * GB + 760 * MB),
                    .file("Prototype interaction.mp4", 630 * MB)
                ])
            ]),
            .folder("Applications", .applications, [
                .folder("Xcode.app", .applications, [.file("Xcode executable & resources", 12 * GB + 180 * MB)]),
                .folder("Final Cut Pro.app", .applications, [.file("Final Cut Pro executable & resources", 5 * GB + 640 * MB)]),
                .folder("Adobe Photoshop.app", .applications, [.file("Photoshop executable & resources", 3 * GB + 780 * MB)]),
                .folder("Figma.app", .applications, [.file("Figma executable & resources", 740 * MB)]),
                .folder("Notion.app", .applications, [.file("Notion executable & resources", 520 * MB)]),
                .folder("Arc.app", .applications, [.file("Arc executable & resources", 680 * MB)]),
                .folder("Visual Studio Code.app", .applications, [.file("Code executable & resources", 610 * MB)])
            ]),
            .folder("Pictures", .media, [
                .folder("Iceland 2025", .media, [
                    .file("Iceland — selects.lrcat", 1 * GB + 850 * MB),
                    .file("Iceland — contact sheet.psd", 940 * MB),
                    .file("DSC_4208.ARW", 87 * MB),
                    .file("DSC_4210.ARW", 86 * MB),
                    .file("DSC_4215.ARW", 91 * MB),
                    .file("DSC_4219.ARW", 89 * MB)
                ]),
                .folder("Brand assets", .media, [
                    .file("Product renders.psd", 2 * GB + 360 * MB),
                    .file("Campaign master.psb", 4 * GB + 120 * MB),
                    .file("Material studies.tiff", 680 * MB)
                ]),
                .file("Photos Library.photoslibrary", 16 * GB + 420 * MB)
            ]),
            .folder("Documents", .documents, [
                .folder("Client work", .documents, [
                    .file("Studio — brand guidelines.pdf", 280 * MB),
                    .file("Pitch — autumn 2026.key", 1 * GB + 480 * MB),
                    .file("Research archive.pdf", 760 * MB),
                    .file("Strategy workshop.pages", 180 * MB)
                ]),
                .folder("Books", .documents, [
                    .file("Design reference collection.pdf", 940 * MB),
                    .file("Typography notes.pdf", 160 * MB),
                    .file("The design of everyday things.epub", 28 * MB)
                ]),
                .file("Annual plan.numbers", 18 * MB),
                .file("Ideas.md", 84_000)
            ]),
            .folder("Downloads", .archives, [
                .file("Project handoff — September.zip", 8 * GB + 240 * MB),
                .file("Stock footage pack.zip", 6 * GB + 780 * MB),
                .file("macOS installer.dmg", 5 * GB + 260 * MB),
                .file("Texture collection.zip", 2 * GB + 180 * MB),
                .file("Figma.dmg", 220 * MB),
                .file("Desktop backup.tar.gz", 1 * GB + 640 * MB)
            ]),
            .folder("Library", .other, [
                .folder("Application Support", .other, [
                    .file("Browser profile.data", 3 * GB + 180 * MB),
                    .file("Messages attachments.data", 2 * GB + 640 * MB),
                    .file("Mail downloads.data", 1 * GB + 920 * MB)
                ]),
                .folder("Caches", .other, [
                    .file("Preview cache.data", 1 * GB + 460 * MB),
                    .file("Browser cache.data", 2 * GB + 180 * MB),
                    .file("Font cache.data", 180 * MB)
                ])
            ])
        ])
        var nodes: [String: DiskNode] = [:]
        let now = Date()

        @discardableResult
        func add(_ entry: DemoEntry, parent: String?, inheritedCategory: FileCategory) -> DiskNode {
            let path = (parent ?? "/Sample") + "/" + entry.name
            let category = entry.category ?? inheritedCategory
            let children: [DiskNode]
            let size: Int64
            switch entry {
            case .folder(_, _, let entries):
                children = entries.map { add($0, parent: path, inheritedCategory: category) }
                size = children.reduce(0) { $0 + $1.logicalSize }
            case .file(_, let bytes):
                children = []
                size = bytes
            }
            let node = DiskNode(id: path, url: URL(fileURLWithPath: path), name: entry.name, isDirectory: entry.isDirectory, logicalSize: size, allocatedSize: entry.isDirectory ? children.reduce(0) { $0 + $1.allocatedSize } : ((size + 4095) / 4096) * 4096, fileCount: entry.isDirectory ? children.reduce(0) { $0 + $1.fileCount } : 1, children: children.map(\.id), parentID: parent, modificationDate: now.addingTimeInterval(-TimeInterval((nodes.count + 1) * 54_000)), category: category)
            nodes[path] = node
            return node
        }
        let root = add(sample, parent: nil, inheritedCategory: .other)
        return DiskSnapshot(rootID: root.id, nodes: nodes, startedAt: now.addingTimeInterval(-4.2), finishedAt: now, visitedFileCount: root.fileCount, isDemo: true)
    }()
}

private indirect enum DemoEntry {
    case folder(String, FileCategory, [DemoEntry])
    case file(String, Int64)

    var name: String {
        switch self {
        case .folder(let name, _, _), .file(let name, _): return name
        }
    }

    var category: FileCategory? {
        if case .folder(_, let category, _) = self { return category }
        return nil
    }

    var isDirectory: Bool {
        if case .folder = self { return true }
        return false
    }
}
