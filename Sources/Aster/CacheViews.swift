import SwiftUI
import AsterCore

struct CacheWorkspaceView: View {
    @Environment(LicenseController.self) private var license
    @Bindable var state: CleanupDiscoveryState
    @Bindable var cleanup: CleanupState

    private var isBusy: Bool { state.isLoading || cleanup.isPreparing || cleanup.isTrashing }
    private var pendingCount: Int { state.selectedEntries.filter { !cleanup.contains($0.url) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            scanNotice
            summaries
            searchAndFilters
            if state.filteredEntries.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(state.filteredEntries.count.formatted()) \(state.filteredEntries.count == 1 ? "location" : "locations")")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("LARGEST FIRST").font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(Theme.muted)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.filteredEntries) { entry in
                            CacheEntryRow(entry: entry, selected: state.selectedIDs.contains(entry.id),
                                          blockedReason: state.blockedReason(for: entry),
                                          disabled: isBusy, queued: cleanup.contains(entry.url),
                                          toggle: { state.toggle(entry.id) }, reveal: { state.reveal(entry.url) })
                        }
                    }.padding(.bottom, 5)
                }.scrollIndicators(.hidden)
            }
            footer
        }
        .padding(26)
        .task { state.loadIfNeeded() }
        .accessibilityIdentifier("cache-workspace")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A fresh start, in the details.")
                    .font(.system(size: 27, weight: .medium)).tracking(-0.8)
                Text("App caches, logs, and developer caches found on your Mac.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Button(action: state.load) {
                Label("Scan caches", systemImage: "arrow.clockwise")
            }.buttonStyle(AccentButtonStyle()).disabled(isBusy)
                .opacity(isBusy ? 0.45 : 1)
                .accessibilityIdentifier("cache-scan")
        }
    }

    private var summaries: some View {
        HStack(spacing: 14) {
            cacheMetric(title: "MEASURED SIZE", value: state.hasLoaded ? sizeString(state.totalBytes) : "—", subtitle: "Logical size, before review", symbol: "chart.pie", color: Theme.accent)
            cacheMetric(title: "LOCATIONS FOUND", value: state.hasLoaded ? state.result.entries.count.formatted() : "—", subtitle: "Only locations present on this Mac", symbol: "folder", color: Theme.mint)
            cacheMetric(title: "YOUR SELECTION", value: "\(state.selectedEntries.count.formatted()) items", subtitle: sizeString(state.selectedBytes) + " logical size", symbol: "checkmark.circle", color: Theme.warning)
        }
    }

    @ViewBuilder private var scanNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            if state.isLoading {
                HStack(spacing: 11) {
                    ProgressView().controlSize(.small)
                    Text(state.hasLoaded ? "Checking cache locations… showing previous results until complete." : "Checking cache locations on this Mac…")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Cancel", action: state.cancel).buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("cache-cancel-scan")
                }.padding(12).background(Theme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            } else if let error = state.errorMessage {
                note(license.isPro ? error : "The cache scan couldn’t finish. Try again or check access permissions.", color: Theme.warning, symbol: "exclamationmark.circle")
            } else if let message = state.statusMessage {
                note(message, color: Theme.secondary, symbol: "info.circle")
            }
            if !state.result.warnings.isEmpty {
                DisclosureGroup {
                    if license.isPro {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(state.result.warnings.enumerated()), id: \.offset) { _, warning in
                                    Text(warning).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(.top, 8)
                        }.frame(maxHeight: 110)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Some cache locations could not be fully checked. Items with incomplete measurements remain protected.")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            ProActionButton("View detailed scan notes", systemImage: "text.alignleft") {}
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                        }.padding(.top, 8)
                    }
                } label: {
                    Text("Scan notes · \(state.result.warnings.count)")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private var searchAndFilters: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Find a cache, app, or path…", text: $state.query)
                    .font(.system(size: 12)).textFieldStyle(.plain)
                    .accessibilityLabel("Search cache locations")
                    .accessibilityIdentifier("cache-search")
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Clear cache search")
                }
            }.padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
            Picker("Cache category", selection: $state.area) {
                Text("All").tag(nil as CleanupArea?)
                Text("App caches").tag(Optional(CleanupArea.caches))
                Text("Logs").tag(Optional(CleanupArea.logs))
                Text("Developer").tag(Optional(CleanupArea.developer))
            }.pickerStyle(.segmented).frame(width: 335)
                .accessibilityIdentifier("cache-category")
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose what to review.").font(.system(size: 12, weight: .medium))
                Text("Caches may be rebuilt or downloaded again. Logs preserve diagnostic history.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !state.selectedIDs.isEmpty {
                Button("Clear selection") { state.selectedIDs = [] }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.secondary).disabled(isBusy)
            }
            Button { state.queueSelected(into: cleanup) } label: {
                Label("Add \(pendingCount) to queue", systemImage: "plus")
            }.buttonStyle(AccentButtonStyle()).disabled(pendingCount == 0 || isBusy)
                .opacity(pendingCount == 0 || isBusy ? 0.45 : 1)
                .accessibilityIdentifier("cache-add-to-queue")
        }.padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: state.isLoading ? "sparkle.magnifyingglass" : "square.stack.3d.up")
                .font(.system(size: 35, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.65))
            Text(state.isLoading ? "Looking beneath the surface…" : state.hasLoaded ? "No matches in this view." : "Your cache locations, in view.")
                .font(.system(size: 18, weight: .medium)).tracking(-0.3)
            Text(state.isLoading ? "Aster is reading file names and sizes." : state.hasLoaded ? "Try another search or category. Scan notes explain any locations that couldn’t be read." : "Scan caches to find the locations that exist on this Mac.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 410).lineSpacing(4)
        }.padding(25)
    }

    private func cacheMetric(title: String, value: String, subtitle: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
            }
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.6)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(subtitle).font(.system(size: 9)).foregroundStyle(Theme.secondary).lineLimit(2)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func note(_ text: String, color: Color, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct CacheEntryRow: View {
    @Environment(LicenseController.self) private var license
    let entry: CleanupDiscoveryEntry
    let selected: Bool
    let blockedReason: String?
    let disabled: Bool
    let queued: Bool
    let toggle: () -> Void
    let reveal: () -> Void

    private var color: Color {
        switch entry.area {
        case .caches: return Theme.mint
        case .logs: return Theme.blue
        case .developer: return Theme.accent
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Toggle("Include \(entry.title)", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().padding(.top, 10)
                .disabled(disabled || blockedReason != nil)
                .accessibilityLabel(license.isPro ? "Include \(entry.title), \(entry.url.path)" : "Include \(entry.title)")
                .accessibilityIdentifier("cache-select-\(license.isPro ? entry.id : entry.title)")
            Image(systemName: cacheAreaSymbol(entry.area))
                .font(.system(size: 17, weight: .light)).foregroundStyle(color)
                .frame(width: 37, height: 38)
                .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.title).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    Text(entry.area.title).font(.system(size: 9)).foregroundStyle(color)
                    if queued {
                        Label("Queued", systemImage: "checkmark").font(.system(size: 9)).foregroundStyle(Theme.mint)
                    }
                    Spacer(minLength: 4)
                }
                ProPathText(url: entry.url)
                Text("\(entry.fileCount.formatted()) \(entry.fileCount == 1 ? "file" : "files")\(entry.isPartial ? " · partial measurement" : "")")
                    .font(.system(size: 9)).foregroundStyle(Theme.muted)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                if let documentation = entry.documentationURL {
                    Link(destination: documentation) {
                        Label("Tool documentation", systemImage: "arrow.up.right")
                            .font(.system(size: 9)).foregroundStyle(Theme.accent)
                    }.help(documentation.absoluteString)
                }
                if let reason = blockedReason {
                    Label(reason, systemImage: "lock")
                        .font(.system(size: 10)).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .trailing, spacing: 12) {
                Text(sizeString(entry.logicalSize))
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.text)
                    .lineLimit(1).fixedSize()
                ProActionButton("Reveal in Finder", systemImage: "arrow.up.forward.app", action: reveal)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .frame(width: 24, height: 22)
                    .accessibilityLabel(license.isPro ? "Reveal \(entry.title) in Finder" : "Unlock Reveal in Finder with Aster Pro")
            }
        }
        .padding(14)
        .background(selected && blockedReason == nil ? Theme.accent.opacity(0.055) : Theme.panel, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected && blockedReason == nil ? Theme.accent.opacity(0.23) : Theme.border, lineWidth: 1))
        .contextMenu { ProActionButton("Reveal in Finder", systemImage: "arrow.up.forward.app", action: reveal) }
        .accessibilityIdentifier("cache-entry-\(license.isPro ? entry.id : entry.title)")
    }
}
