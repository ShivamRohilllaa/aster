import SwiftUI
import AsterCore

struct OverviewView: View {
    @Bindable var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little clarity. A lot of space.")
                        .font(.system(size: 27, weight: .medium)).tracking(-0.8)
                    Text(state.hasScannedFolder ? "Your files, seen from a different perspective." : "Reading the files on your Mac. Everything here comes from your storage.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                if state.hasScannedFolder {
                HStack(spacing: 12) {
                    MetricView(title: "SCANNED SIZE", value: sizeString(state.snapshot.root.logicalSize), subtitle: "Logical file size", symbol: "chart.pie", color: Theme.accent)
                    MetricView(title: "FILES INDEXED", value: state.snapshot.visitedFileCount.formatted(), subtitle: "Ready to explore", symbol: "doc.on.doc", color: Theme.mint)
                    MetricView(title: "SCAN TIME", value: "\(state.snapshot.duration.formatted(.number.precision(.fractionLength(1))))s", subtitle: "Processed on this Mac", symbol: "bolt", color: Theme.warning)
                }
                storageMap
                largestFiles
                } else {
                    firstScan
                }
            }.padding(26)
        }.scrollIndicators(.hidden)
    }

    private var firstScan: some View {
        Panel(padding: 30) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 17) {
                    Image(systemName: "internaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(state.isScanning ? "Getting to know your storage." : "Choose where to look.")
                            .font(.system(size: 21, weight: .medium)).tracking(-0.5)
                        ProPathText(url: state.scanURL ?? state.snapshot.root.url)
                    }
                }
                if state.isScanning {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    HStack {
                        Text("\(state.progress?.fileCount.formatted() ?? "0") files found")
                        Spacer()
                        Text("\(sizeString(state.progress?.logicalBytes ?? 0)) indexed so far")
                    }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text("Names and sizes only. Your files stay on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                } else {
                    Text("Scan a folder or disk to build its storage map and find large files.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Button("Choose a folder", action: state.chooseFolder).buttonStyle(AccentButtonStyle())
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storageMap: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Storage map").font(.system(size: 15, weight: .semibold))
                        Text("Every block tells a story. Larger blocks use more space.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(sizeString(state.mapRoot.logicalSize)).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 7) {
                    Button {
                        if let parent = state.mapRoot.parentID { state.navigate(to: parent) }
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 22)
                    }.buttonStyle(.plain).disabled(state.mapRoot.parentID == nil)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 5))
                        .help("Go to parent folder")
                    ForEach(Array(state.breadcrumbs.suffix(4).enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.muted) }
                        Button(node.name) { state.navigate(to: node.id) }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(node.id == state.mapRootID ? Theme.text : Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("Double-click to explore").font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
                StorageMapView(snapshot: state.snapshot, rootID: state.mapRootID, selectedID: state.selectedID,
                               onSelect: { state.selectedID = $0 }, onOpen: { state.navigate(to: $0) })
                    .frame(height: 267)
                HStack(spacing: 13) {
                    ForEach(FileCategory.allCases, id: \.self) { category in
                        HStack(spacing: 5) {
                            Circle().fill(category.tint).frame(width: 5, height: 5)
                            Text(category.displayName).font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var largestFiles: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Room to rediscover").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { state.showFiles() } label: {
                    HStack(spacing: 5) { Text("View all files"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                }.buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                if state.overviewFiles.isEmpty {
                    Text("No files to show yet.").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(20)
                } else {
                    ForEach(Array(state.overviewFiles.prefix(3).enumerated()), id: \.element.id) { index, node in
                        FileRow(node: node, root: state.snapshot.root, selected: state.selectedID == node.id, compact: true) {
                            state.selectedID = node.id
                        }
                        if index < min(2, state.overviewFiles.count - 1) { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 49) }
                    }
                }
            }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        }
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(Theme.secondary)
                Spacer()
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.7).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(subtitle).font(.system(size: 9)).foregroundStyle(Theme.muted)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}
