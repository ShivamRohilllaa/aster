import SwiftUI
import AsterCore

/// A bounded, proportional view of a folder's immediate contents. Descend into a
/// folder to reveal more detail; smaller siblings are grouped without inflating them.
struct StorageMapView: View {
    let snapshot: DiskSnapshot
    let rootID: String
    let selectedID: String?
    let onSelect: (String) -> Void
    let onOpen: (String) -> Void
    private let entries: [StorageMapEntry]

    init(snapshot: DiskSnapshot, rootID: String, selectedID: String?,
         onSelect: @escaping (String) -> Void, onOpen: @escaping (String) -> Void) {
        self.snapshot = snapshot
        self.rootID = rootID
        self.selectedID = selectedID
        self.onSelect = onSelect
        self.onOpen = onOpen
        let children = snapshot.nodes[rootID]?.children.compactMap { snapshot.nodes[$0] } ?? []
        self.entries = StorageMapEntry.make(from: children, limit: 40, groupID: "group:\(rootID)")
    }

    var body: some View {
        GeometryReader { geometry in
            if entries.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let rectangles = TreemapLayout.rectangles(
                    for: entries.map { TreemapItem(id: $0.id, weight: $0.bytes) },
                    in: CGRect(origin: .zero, size: geometry.size)
                )
                let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
                ZStack(alignment: .topLeading) {
                    ForEach(rectangles) { tile in
                        if let entry = byID[tile.id], tile.rect.width > 7, tile.rect.height > 7 {
                            StorageMapTile(
                                entry: entry,
                                children: tile.rect.width > 195 && tile.rect.height > 205 ? nestedEntries(for: entry) : [],
                                size: CGSize(width: max(0, tile.rect.width - 5), height: max(0, tile.rect.height - 5)),
                                isSelected: entry.nodeID != nil && entry.nodeID == selectedID,
                                onSelect: { if let id = entry.nodeID { onSelect(id) } },
                                onOpen: { if let id = entry.nodeID { onOpen(id) } }
                            )
                            .frame(width: max(0, tile.rect.width - 5), height: max(0, tile.rect.height - 5))
                            .offset(x: tile.rect.minX + 2.5, y: tile.rect.minY + 2.5)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage map")
    }

    private func nestedEntries(for entry: StorageMapEntry) -> [StorageMapEntry] {
        guard entry.isDirectory, let nodeID = entry.nodeID,
              let node = snapshot.nodes[nodeID] else { return [] }
        return StorageMapEntry.make(from: node.children.compactMap { snapshot.nodes[$0] },
                                    limit: 2, groupID: "nested:\(nodeID)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Theme.muted)
            Text("Nothing taking up space")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
            Text("This folder has no readable, non-empty files.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
    }
}

private struct StorageMapEntry: Identifiable {
    let id: String
    let nodeID: String?
    let name: String
    let bytes: Double
    let category: FileCategory
    let isDirectory: Bool
    let itemCount: Int

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, Double(Int64.max - 2048))), countStyle: .file)
    }

    static func make(from nodes: [DiskNode], limit: Int, groupID: String) -> [Self] {
        let sorted = nodes.filter { $0.logicalSize > 0 }.sorted {
            if $0.logicalSize == $1.logicalSize { return $0.id < $1.id }
            return $0.logicalSize > $1.logicalSize
        }
        let visibleCount = sorted.count <= limit ? sorted.count : max(0, limit - 1)
        var entries = sorted.prefix(visibleCount).map { node in
            Self(id: node.id, nodeID: node.id, name: node.name, bytes: Double(node.logicalSize),
                 category: node.category, isDirectory: node.isDirectory, itemCount: node.fileCount)
        }
        if visibleCount < sorted.count {
            let remainder = sorted.dropFirst(visibleCount)
            entries.append(Self(id: groupID, nodeID: nil, name: "\(remainder.count.formatted()) smaller items",
                                bytes: remainder.reduce(0.0) { $0 + Double($1.logicalSize) },
                                category: .other, isDirectory: false, itemCount: remainder.count))
        }
        return entries
    }
}

private struct StorageMapTile: View {
    let entry: StorageMapEntry
    let children: [StorageMapEntry]
    let size: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var accent: Color { isLight ? entry.category.tint : entry.category.mapColor }
    private var gradientTopOpacity: Double { isLight ? (isHovered ? 0.19 : 0.12) : (isHovered ? 0.47 : 0.34) }
    private var gradientBottomOpacity: Double { isLight ? (isHovered ? 0.10 : 0.055) : (isHovered ? 0.27 : 0.18) }
    private var roomy: Bool { size.width > 155 && size.height > 120 }
    private var showNested: Bool { size.width > 190 && size.height > 200 && !children.isEmpty }
    private var padding: CGFloat { roomy ? 17 : 10 }

    var body: some View {
        Group {
            if entry.nodeID != nil {
                Button(action: onSelect) { surface }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if entry.isDirectory { onOpen() }
                    })
                    .contextMenu {
                        if entry.isDirectory {
                            Button("Open folder", systemImage: "folder") { onOpen() }
                        }
                        Button("View details", systemImage: "info.circle") { onSelect() }
                    }
                    .accessibilityLabel("\(entry.name), \(entry.sizeLabel), \(entry.isDirectory ? "folder" : "file")")
                    .accessibilityHint(entry.isDirectory ? "Select for details. Double-click to explore folder." : "Select to view file details.")
                    .accessibilityAction(named: Text("View details"), onSelect)
                    .accessibilityAction(named: Text(entry.isDirectory ? "Open folder" : "Select file")) {
                        entry.isDirectory ? onOpen() : onSelect()
                    }
            } else {
                surface
                    .accessibilityLabel("\(entry.name), \(entry.sizeLabel), grouped for display")
            }
        }
        .onHover { isHovered = $0 }
        .help(entry.nodeID == nil
              ? "\(entry.name) · \(entry.sizeLabel)\nGrouped to keep the map readable. Use the file list to inspect individual items."
              : "\(entry.name) · \(entry.sizeLabel)\(entry.isDirectory ? "\nDouble-click to explore" : "")")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
    }

    private var surface: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: roomy ? 10 : 7, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(gradientTopOpacity), accent.opacity(gradientBottomOpacity)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if size.width > 64 && size.height > 38 {
                content.padding(padding)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: roomy ? 10 : 7, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.98) : accent.opacity(isHovered ? 0.70 : 0.26), lineWidth: isSelected ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: roomy ? 10 : 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: roomy ? 10 : 7, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: roomy ? 9 : 4) {
            HStack(alignment: .top, spacing: 7) {
                if size.width > 115 {
                    Image(systemName: entry.nodeID == nil ? "square.grid.2x2.fill" : (entry.isDirectory ? "folder.fill" : entry.category.mapSymbol))
                        .font(.system(size: roomy ? 12 : 10, weight: .medium))
                        .foregroundStyle(accent.opacity(0.95))
                        .padding(.top, 1)
                }
                Text(entry.name)
                    .font(.system(size: roomy ? 13 : 11, weight: .semibold))
                    .foregroundStyle(isLight ? Theme.text : Color.white.opacity(isHovered ? 1 : 0.88))
                    .lineLimit(roomy ? 2 : 1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if roomy && entry.isDirectory && isHovered {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isLight ? Theme.secondary : Color.white.opacity(0.5))
                        .accessibilityHidden(true)
                }
            }
            if size.height > 64 {
                Text(entry.sizeLabel)
                    .font(.system(size: roomy ? 25 : 12, weight: roomy ? .medium : .regular, design: .rounded))
                    .tracking(roomy ? -0.6 : 0)
                    .foregroundStyle(isLight ? (roomy ? Theme.text : Theme.secondary) : Color.white.opacity(roomy ? 0.96 : 0.57))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if showNested {
                nestedTiles
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: 0)
            }
            if roomy {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 4, height: 4)
                    Text(entry.category.mapLabel.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.1)
                    Spacer(minLength: 4)
                    if entry.isDirectory && size.width > 215 {
                        Text("\(entry.itemCount.formatted()) files")
                            .font(.system(size: 9))
                    }
                }
                .foregroundStyle(isLight ? Theme.secondary : Color.white.opacity(0.42))
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var nestedTiles: some View {
        GeometryReader { geometry in
            let rectangles = TreemapLayout.rectangles(
                for: children.map { TreemapItem(id: $0.id, weight: $0.bytes) },
                in: CGRect(origin: .zero, size: geometry.size)
            )
            ZStack(alignment: .topLeading) {
                ForEach(rectangles) { rectangle in
                    if rectangle.rect.width > 9 && rectangle.rect.height > 9,
                       let child = children.first(where: { $0.id == rectangle.id }) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(accent.opacity(isLight ? 0.035 : 0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(accent.opacity(0.13), lineWidth: 1)
                            }
                            .overlay(alignment: .bottomLeading) {
                                if rectangle.rect.width > 90 && rectangle.rect.height > 35 {
                                    Text(child.name)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(isLight ? Theme.secondary : Color.white.opacity(0.27))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(8)
                                }
                            }
                            .frame(width: max(0, rectangle.rect.width - 4), height: max(0, rectangle.rect.height - 4))
                            .offset(x: rectangle.rect.minX + 2, y: rectangle.rect.minY + 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension FileCategory {
    var mapColor: Color {
        switch self {
        case .developer: return Color(red: 0.58, green: 0.46, blue: 1)
        case .documents: return Color(red: 0.35, green: 0.59, blue: 1)
        case .media: return Color(red: 0.22, green: 0.76, blue: 0.77)
        case .archives: return Color(red: 0.91, green: 0.69, blue: 0.34)
        case .applications: return Color(red: 0.91, green: 0.43, blue: 0.61)
        case .other: return Color(red: 0.49, green: 0.55, blue: 0.68)
        }
    }

    var mapLabel: String {
        switch self {
        case .developer: return "Developer"
        case .documents: return "Documents"
        case .media: return "Media"
        case .archives: return "Archives"
        case .applications: return "Applications"
        case .other: return "Other"
        }
    }

    var mapSymbol: String {
        switch self {
        case .developer: return "curlybraces"
        case .documents: return "doc.fill"
        case .media: return "photo.fill"
        case .archives: return "archivebox.fill"
        case .applications: return "app.fill"
        case .other: return "doc.fill"
        }
    }
}
