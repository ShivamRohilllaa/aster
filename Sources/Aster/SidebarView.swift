import SwiftUI
import AsterCore

struct SidebarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AsterMark()
                Text("aster").font(.system(size: 26, weight: .semibold, design: .rounded)).tracking(-1)
            }.padding(.top, 29).padding(.bottom, 25).padding(.leading, 24)

            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            SectionEyebrow(text: "Workspace").padding(.leading, 25).padding(.bottom, 12)
            ForEach([AppSection.overview, .largeFiles], id: \.self) { section in
                sidebarRow(section.rawValue, icon: section.symbol, selected: state.section == section && state.category == nil) {
                    state.section = section
                    state.category = nil
                }
            }
            SectionEyebrow(text: "Make room").padding(.leading, 25).padding(.top, 22).padding(.bottom, 10)
            ForEach([AppSection.cleanup, .caches, .applications, .leftovers], id: \.self) { section in
                sidebarRow(section.rawValue, icon: section.symbol, selected: state.section == section) {
                    state.section = section
                    state.category = nil
                }
            }

            SectionEyebrow(text: "Collections").padding(.leading, 25).padding(.top, 22).padding(.bottom, 10)
            ForEach(FileCategory.allCases, id: \.self) { category in
                Button { state.showFiles(category: category) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(category.tint).frame(width: 6, height: 6).frame(width: 12)
                        Text(category.displayName).font(.system(size: 11)).lineLimit(1).layoutPriority(1)
                        Spacer()
                        if let bytes = state.categoryTotals[category], bytes > 0 {
                            Text(sizeString(bytes)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    .foregroundStyle(state.category == category ? Theme.text : Theme.secondary)
                    .padding(.horizontal, 13).frame(height: 34)
                    .background(state.category == category ? Theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }
            }.padding(.bottom, 18)
            }.scrollIndicators(.hidden)
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive").font(.system(size: 19)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(state.isScanning ? "SCANNING" : state.hasScannedFolder ? (state.snapshot.isPartial ? "PARTIAL SCAN" : "SCANNED") : "YOUR MAC").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
                }
                Text(state.snapshot.root.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.hasScannedFolder ? sizeString(state.snapshot.root.logicalSize) : "—").font(.system(size: 22, weight: .medium, design: .rounded)).tracking(-0.8)
                }
                categoryBar
                Text(state.hasScannedFolder ? "\(state.snapshot.visitedFileCount.formatted()) files in this scan" : "Your files are being indexed")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 20)
            Button { openWindow(id: "license") } label: {
                HStack(spacing: 9) {
                    Image(systemName: state.license.isPro ? "checkmark.seal.fill" : "sparkles")
                    Text(!state.license.requiresLicense ? "All features free" : state.license.isPro ? "Aster Pro" : "Discover Aster Pro")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    .padding(12).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 16)
                .accessibilityIdentifier("open-aster-license")
            SettingsLink {
                HStack(spacing: 9) {
                    Image(systemName: "paintpalette")
                    Text("Appearance")
                    Spacer()
                    Image(systemName: "gearshape").font(.system(size: 10))
                }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 15)
                .help("Choose Light or Dark appearance (⌘,)")
            Button { state.sheet = .about } label: {
                HStack {
                    Image(systemName: "sparkle")
                    Text("About Aster")
                    Spacer()
                    Text("0.4").font(.system(size: 10, design: .monospaced))
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 22)
        }.background(Theme.sidebar)
    }

    private var categoryBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(FileCategory.allCases, id: \.self) { category in
                    let total = max(1, state.categoryTotals.values.reduce(0, +))
                    let proportion = Double(state.categoryTotals[category] ?? 0) / Double(total)
                    if proportion > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(category.tint)
                            .frame(width: max(1, (geometry.size.width - 10) * proportion))
                    }
                }
            }
        }.frame(height: 4)
    }

    private func sidebarRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 16)
                Text(title).font(.system(size: 12, weight: selected ? .medium : .regular))
                Spacer()
                if selected { Circle().fill(Theme.accent).frame(width: 4, height: 4) }
            }.foregroundStyle(selected ? Theme.accent : Theme.secondary)
                .padding(.horizontal, 13).frame(height: 38)
                .background(selected ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
    }
}
