import SwiftUI
import AsterCore

struct InspectorView: View {
    @Bindable var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    SectionEyebrow(text: "A closer look")
                    Spacer()
                    Image(systemName: "sidebar.right").foregroundStyle(Theme.muted).font(.system(size: 12))
                }
                if let node = state.selectedNode {
                    selectedDetails(node)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cursorarrow.click").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Theme.accent)
                        Text("Follow your curiosity.").font(.system(size: 15, weight: .medium))
                        Text("Select a block or file to see its details here.").font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                }
            }.padding(.horizontal, 22).padding(.top, 29).padding(.bottom, 24)
        }.scrollIndicators(.hidden).background(Theme.sidebar.opacity(0.35))
    }

    private func selectedDetails(_ node: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(node.category.tint.opacity(0.08))
                    RoundedRectangle(cornerRadius: 16).stroke(node.category.tint.opacity(0.14), lineWidth: 1)
                    Image(systemName: node.isDirectory ? "folder.fill" : node.category.symbol)
                        .font(.system(size: 29, weight: .light)).foregroundStyle(node.category.tint.gradient)
                }.frame(width: 67, height: 67)
                Text(node.name).font(.system(size: 19, weight: .medium)).tracking(-0.4).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 6) {
                    Circle().fill(node.category.tint).frame(width: 5, height: 5)
                    Text(node.isDirectory ? "Folder · \(node.category.displayName)" : node.category.displayName)
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Logical size")
                Text(sizeString(node.logicalSize)).font(.system(size: 31, weight: .light, design: .rounded)).tracking(-1)
                GeometryReader { geo in
                    let fraction = min(1, max(0, Double(node.logicalSize) / Double(max(1, state.snapshot.root.logicalSize))))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.elevated)
                        Capsule().fill(node.category.tint).frame(width: max(0, geo.size.width * fraction))
                    }
                }.frame(height: 4)
                let percent = Double(node.logicalSize) / Double(max(1, state.snapshot.root.logicalSize)) * 100
                Text("\(percent.formatted(.number.precision(.fractionLength(1))))% of this scan")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            VStack(spacing: 14) {
                detailRow("Allocated", value: sizeString(node.allocatedSize))
                if node.isDirectory {
                    detailRow("Files inside", value: node.fileCount.formatted())
                    detailRow("Direct items", value: node.children.count.formatted())
                }
                if let modified = node.modificationDate {
                    detailRow("Modified", value: modified.formatted(date: .abbreviated, time: .omitted))
                }
                if node.isSymbolicLink { detailRow("Type", value: "Symbolic link") }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Location")
                ProPathText(url: node.url)
                    .padding(11).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(spacing: 9) {
                Button { state.queueForCleanup(node) } label: {
                    HStack {
                        Image(systemName: state.cleanup.contains(node.url) ? "checkmark" : "tray.and.arrow.down")
                        Text(state.cleanup.contains(node.url) ? "In cleanup queue" : "Add to cleanup")
                        Spacer()
                    }
                }.buttonStyle(QuietButtonStyle())
                    .disabled(state.cleanup.contains(node.url) || state.cleanup.isPreparing || state.cleanup.isTrashing)
                    .accessibilityIdentifier("add-to-cleanup")
                if node.isDirectory {
                    Button { state.navigate(to: node.id) } label: {
                        HStack { Text("Explore folder"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(AccentButtonStyle()).disabled(node.id == state.mapRootID)
                } else if let parentID = node.parentID {
                    Button { state.navigate(to: parentID) } label: {
                        HStack { Text("Show folder on map"); Spacer(); Image(systemName: "square.grid.2x2") }
                    }.buttonStyle(AccentButtonStyle())
                }
                ProActionButton("Reveal in Finder", systemImage: "arrow.up.forward.app") { state.reveal(node) }
                    .buttonStyle(QuietButtonStyle())
                ProActionButton("Copy path", systemImage: "doc.on.doc") { state.copyPath(node) }
                    .buttonStyle(QuietButtonStyle())
            }
                Label("Allocated size is an estimate. Shared blocks and snapshots can affect actual disk usage.", systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
        }
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Theme.muted)
            Spacer(minLength: 5)
            Text(value).foregroundStyle(Theme.secondary).multilineTextAlignment(.trailing)
        }.font(.system(size: 10))
    }
}
