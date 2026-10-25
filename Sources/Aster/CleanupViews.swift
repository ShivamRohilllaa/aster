import SwiftUI
import AsterCore

struct CleanupWorkspaceView: View {
    @Bindable var state: CleanupState
    var findFiles: () -> Void = {}
    var findApplications: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 23)
            if state.queue.isEmpty && state.results.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let message = state.errorMessage {
                            CleanupMessage(text: message, symbol: "exclamationmark.circle", color: Theme.warning)
                        } else if let message = state.statusMessage {
                            CleanupMessage(text: message, symbol: "info.circle", color: Theme.secondary)
                        }
                        if !state.queue.isEmpty { queueList }
                        if !state.results.isEmpty { resultList }
                    }.padding(.horizontal, 26).padding(.bottom, 26)
                }.scrollIndicators(.hidden)
            }
            footer
        }
        .accessibilityIdentifier("cleanup-workspace")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Make room, thoughtfully.")
                    .font(.system(size: 27, weight: .medium)).tracking(-0.8)
                Text("A considered collection. Review every item before it moves.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 22) {
                cleanupMetric("IN YOUR QUEUE", value: "\(state.queue.count.formatted()) \(state.queue.count == 1 ? "item" : "items")")
                Rectangle().fill(Theme.border).frame(width: 1, height: 33)
                cleanupMetric("KNOWN LOGICAL SIZE", value: state.queue.contains(where: { $0.logicalSize != nil }) ? sizeString(state.queueBytes) : "—")
                Spacer(minLength: 0)
                if !state.queue.isEmpty {
                    Button("Clear queue", action: state.clear)
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .disabled(state.isPreparing || state.isTrashing)
                        .accessibilityIdentifier("cleanup-clear-queue")
                }
            }
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Ready for review")
                Spacer()
            }
            LazyVStack(spacing: 9) {
                ForEach(state.queue) { item in
                    CleanupQueueRow(item: item, disabled: state.isPreparing || state.isTrashing,
                                    remove: { state.remove(id: item.id) }, reveal: { state.reveal(item.url) })
                }
            }
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last review").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(resultSummary).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            LazyVStack(spacing: 9) {
                ForEach(state.results) { item in
                    CleanupResultRow(item: item, reveal: { state.revealTrash(item) })
                }
            }
        }.padding(.top, state.queue.isEmpty ? 0 : 8)
    }

    private var resultSummary: String {
        let moved = state.results.filter { $0.status == .moved }.count
        let remaining = state.results.count - moved
        return "\(moved.formatted()) moved" + (remaining > 0 ? " · \(remaining.formatted()) not moved" : "")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Theme.accent)
                Text(trashDisclosure)
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if state.isPreparing || state.isTrashing {
                    ProgressView().controlSize(.small)
                    Text(state.isTrashing ? "Moving selected items…" : "Checking your selection…")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(state.isTrashing ? "Stop remaining" : "Cancel", action: state.cancelOperation)
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("cleanup-cancel-operation")
                } else {
                    Text(state.hasProAccess ? "Nothing moves until you confirm." : "Free preview · Moving files to Trash requires Pro.")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Button(action: state.prepareReview) {
                        HStack(spacing: 8) {
                            Text("Review for Trash")
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(AccentButtonStyle()).disabled(!state.canPrepare)
                    .opacity(state.canPrepare ? 1 : 0.45)
                    .accessibilityIdentifier("cleanup-prepare-review")
                }
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 19)
        .background(Theme.sidebar.opacity(0.45))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 21).fill(Theme.accent.opacity(0.07))
                Image(systemName: "tray").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
            }.frame(width: 83, height: 83)
            Text("A little space to decide.")
                .font(.system(size: 19, weight: .medium)).tracking(-0.3)
            Text(state.hasProAccess
                 ? "Add files or app leftovers to your queue.\nReview the full paths and confirm what moves to Trash."
                 : "Add files or app leftovers to your queue.\nReview names and sizes here. Pro unlocks full paths and cleanup.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing: 10) {
                Button("Find large files", action: findFiles).buttonStyle(AccentButtonStyle())
                Button("Review applications", action: findApplications).buttonStyle(QuietButtonStyle())
            }.padding(.top, 5)
        }.padding(28)
    }

    private func cleanupMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).tracking(-0.5)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

struct CleanupReviewSheet: View {
    @Bindable var state: CleanupState
    @Environment(\.openWindow) private var openWindow
    @State private var showsConfirmation = false

    private var rows: [CleanupPreviewRow] { state.review?.items ?? [] }
    private var isBusy: Bool { state.isPreparing || state.isTrashing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(25)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let error = state.errorMessage {
                        CleanupMessage(text: error, symbol: "exclamationmark.circle", color: Theme.warning)
                    }
                    if let review = state.review {
                        ForEach(Array(review.notes.enumerated()), id: \.offset) { _, note in
                            CleanupMessage(text: note, symbol: "info.circle", color: Theme.secondary)
                        }
                    }
                    ForEach(rows) { item in
                        CleanupPreviewItemRow(
                            item: item,
                            selected: state.selectedPreviewIDs.contains(item.id),
                            disabled: isBusy || item.blockedReason != nil,
                            toggle: { state.togglePreviewItem(id: item.id) }
                        )
                    }
                    if rows.isEmpty {
                        Text(state.isPreparing ? "Checking items…" : "There are no items to review.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                }.padding(21)
            }.frame(height: 340)
            Rectangle().fill(Theme.border).frame(height: 1)
            footer.padding(25)
        }
        .frame(width: 740)
        .background(Theme.background).foregroundStyle(Theme.text)
        .interactiveDismissDisabled(isBusy)
        .accessibilityIdentifier("cleanup-review-sheet")
        .confirmationDialog(
            "Move \(state.selectedCount) \(state.selectedCount == 1 ? "item" : "items") to Trash?",
            isPresented: $showsConfirmation, titleVisibility: .visible
        ) {
            Button("Move \(state.selectedCount) \(state.selectedCount == 1 ? "item" : "items") to Trash", role: .destructive) {
                guard state.canConfirm else { return }
                state.confirmTrash()
            }.accessibilityIdentifier("cleanup-confirm-trash")
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text("You selected \(sizeString(state.selectedBytes)) of logical file size across \(state.selectedFileCount.formatted()) included files. \(trashDisclosure)")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    SectionEyebrow(text: "Your final look")
                    Text("Review your selection")
                        .font(.system(size: 25, weight: .medium)).tracking(-0.7)
                    Text("Choose the exact items you want to move to Trash.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button(action: state.dismissReview) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(QuietButtonStyle()).disabled(isBusy)
                .accessibilityLabel("Close cleanup review")
            }
            HStack(spacing: 18) {
                Label("\(state.selectedCount.formatted()) selected", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.accent)
                Text("\(sizeString(state.selectedBytes)) logical size").foregroundStyle(Theme.text)
                Spacer()
                Text("\(state.selectedFileCount.formatted()) included \(state.selectedFileCount == 1 ? "file" : "files")")
                    .foregroundStyle(Theme.secondary)
                    .help("Includes files nested inside the selected folders.")
            }.font(.system(size: 11, weight: .medium))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(trashDisclosure, systemImage: "trash")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 11) {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text(state.isTrashing ? "Moving selected items…" : "Checking your selection…")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(state.isTrashing ? "Stop remaining" : "Cancel", action: state.cancelOperation)
                        .buttonStyle(QuietButtonStyle())
                } else {
                    Button("Back to queue", action: state.dismissReview).buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button {
                        if state.hasProAccess { showsConfirmation = true }
                        else { openWindow(id: "license") }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: state.hasProAccess ? "trash" : "sparkles")
                            Text(state.hasProAccess ? "Move \(state.selectedCount) \(state.selectedCount == 1 ? "item" : "items") to Trash…" : "Unlock cleanup with Pro…")
                        }
                    }
                    .buttonStyle(AccentButtonStyle()).disabled(!state.canConfirm)
                    .opacity(state.canConfirm ? 1 : 0.45)
                    .accessibilityIdentifier("cleanup-open-confirmation")
                }
            }
        }
    }
}

private struct CleanupQueueRow: View {
    @Environment(LicenseController.self) private var license
    let item: CleanupCandidate
    let disabled: Bool
    let remove: () -> Void
    let reveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 37, height: 39)
                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                    Spacer(minLength: 10)
                    Text(item.logicalSize.map(sizeString) ?? "Check in review")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                }
                CleanupExactPath(url: item.url)
                HStack(alignment: .top, spacing: 5) {
                    Text(item.kind).fontWeight(.medium)
                    Text("·")
                    Text(item.reason)
                }.font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted).frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(disabled)
                .help("Remove from queue")
                .accessibilityLabel("Remove \(item.title) from cleanup queue")
        }
        .padding(15)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .contextMenu {
            ProActionButton("Reveal in Finder", action: reveal)
            Button("Remove from queue", action: remove).disabled(disabled)
        }
        .accessibilityIdentifier("cleanup-queue-item-\(license.isPro ? item.id : item.title)")
    }
}

private struct CleanupPreviewItemRow: View {
    @Environment(LicenseController.self) private var license
    let item: CleanupPreviewRow
    let selected: Bool
    let disabled: Bool
    let toggle: () -> Void

    private var isBlocked: Bool { item.blockedReason != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { selected }, set: { _ in toggle() })) {
                Text("Include \(item.title)")
            }
            .toggleStyle(.checkbox).labelsHidden().disabled(disabled)
            .padding(.top, 1)
            .accessibilityLabel("Include \(item.title) in Trash selection")
            .accessibilityIdentifier("cleanup-select-\(license.isPro ? item.id : item.title)")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                    Spacer(minLength: 6)
                    Text(sizeString(item.logicalSize))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondary).fixedSize()
                }
                CleanupExactPath(url: item.url)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(item.fileCount.formatted()) included \(item.fileCount == 1 ? "file" : "files")")
                        .foregroundStyle(Theme.muted)
                    Text("·").foregroundStyle(Theme.muted)
                    Text(item.reason).foregroundStyle(Theme.secondary)
                }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                if let reason = item.blockedReason {
                    Label(reason, systemImage: "lock")
                        .font(.system(size: 10)).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(item.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(15)
        .background(selected && !isBlocked ? Theme.accent.opacity(0.055) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected && !isBlocked ? Theme.accent.opacity(0.23) : Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleanup-review-item-\(license.isPro ? item.id : item.title)")
    }
}

private struct CleanupResultRow: View {
    @Environment(LicenseController.self) private var license
    let item: CleanupOutcome
    let reveal: () -> Void

    private var moved: Bool { item.status == .moved }
    private var color: Color { moved ? Theme.mint : Theme.warning }
    private var statusLabel: String {
        switch item.status {
        case .moved: return "Moved to Trash"
        case .failed: return "Couldn’t move"
        case .skipped: return "Skipped"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: moved ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 17, weight: .light)).foregroundStyle(color)
                .padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    Spacer()
                    Text(statusLabel).font(.system(size: 9, weight: .medium)).foregroundStyle(color)
                }
                CleanupExactPath(url: item.url)
                Text(item.message).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if moved && item.trashURL != nil {
                    ProActionButton("Reveal in Trash", systemImage: "arrow.up.forward.app", action: reveal)
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("Reveal \(item.title) in Trash")
                        .accessibilityIdentifier("cleanup-reveal-trash-\(license.isPro ? item.id : item.title)")
                }
            }
        }
        .padding(15).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

private struct CleanupExactPath: View {
    let url: URL
    var body: some View {
        ProPathText(url: url)
    }
}

private struct CleanupMessage: View {
    let text: String
    let symbol: String
    let color: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11)).foregroundStyle(color)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13).background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }
}

private let trashDisclosure = "Moves to Trash; does not empty Trash. Space is not reclaimed until Trash is emptied."
