import SwiftUI
import AsterCore

struct LargeFilesView: View {
    @Bindable var state: AppState
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.category?.displayName ?? "Find your space.")
                    .font(.system(size: 27, weight: .medium)).tracking(-0.8)
                Text("The files that make a difference, all in one place.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                TextField("Search file names or paths…", text: $state.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityLabel("Search files").accessibilityIdentifier("file-search")
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain)
                }
                if state.isSearching { ProgressView().controlSize(.mini) }
            }.padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1))

            HStack(spacing: 12) {
                Picker("Size", selection: $state.minimumSize) {
                    Text("Any size").tag(Int64(0))
                    Text("100 MB and up").tag(Int64(100_000_000))
                    Text("1 GB and up").tag(Int64(1_000_000_000))
                    Text("5 GB and up").tag(Int64(5_000_000_000))
                }.labelsHidden().frame(width: 131)
                Picker("Sort files", selection: $state.sort) {
                    ForEach(FileSort.allCases, id: \.self) { sort in Text(sort.rawValue).tag(sort) }
                }.labelsHidden().frame(width: 155)
                Spacer(minLength: 0)
                if state.category != nil || state.minimumSize > 0 || !state.query.isEmpty {
                    Button("Reset", action: state.resetFilters).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }.controlSize(.small)
            HStack {
                Text("\(state.matchingCount.formatted()) \(state.matchingCount == 1 ? "file" : "files")").font(.system(size: 11, weight: .medium))
                Text("· \(sizeString(state.matchingBytes)) logical size").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                if state.matchingCount > state.files.count {
                    Text("Showing first \(state.files.count)").font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
            }
            if state.files.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 37, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.65))
                    Text("A little more room to look.").font(.system(size: 17, weight: .medium))
                    Text("No files match these filters. Try another name or a smaller size.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    Button("Clear filters", action: state.resetFilters).buttonStyle(QuietButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(state.files) { node in
                            FileRow(node: node, root: state.snapshot.root, selected: state.selectedID == node.id) {
                                state.selectedID = node.id
                            }
                            .contextMenu {
                                Button(state.cleanup.contains(node.url) ? "In cleanup queue" : "Add to cleanup") { state.queueForCleanup(node) }
                                    .disabled(state.cleanup.contains(node.url) || state.cleanup.isPreparing || state.cleanup.isTrashing)
                                ProActionButton("Reveal in Finder") { state.reveal(node) }
                                ProActionButton("Copy path", systemImage: "doc.on.doc") { state.copyPath(node) }
                            }
                        }
                    }
                }.background(Theme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(26)
    }
}

struct FileRow: View {
    @Environment(LicenseController.self) private var license
    let node: DiskNode
    let root: DiskNode
    let selected: Bool
    var compact = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: node.category.symbol)
                    .font(.system(size: 14, weight: .regular)).foregroundStyle(node.category.tint)
                    .frame(width: 31, height: 34)
                    .background(node.category.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(license.isPro ? relativePath(node, root: root) : "File location · Pro")
                        .font(.system(size: 9)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 10)
                Text(sizeString(node.logicalSize)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 13).padding(.vertical, compact ? 9 : 12)
                .background(selected ? Theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(node.name), \(sizeString(node.logicalSize))")
    }
}
