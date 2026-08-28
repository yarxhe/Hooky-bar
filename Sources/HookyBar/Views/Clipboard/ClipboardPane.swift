import AppKit
import Combine
import SwiftUI

private enum ClipboardFilter: CaseIterable, Identifiable {
    case all
    case text
    case screenshots
    case pinned

    var id: Self { self }
    var title: String {
        switch self {
        case .all: L10n.tr("clipboard.filter.all")
        case .text: L10n.tr("clipboard.filter.text")
        case .screenshots: L10n.tr("clipboard.filter.screenshots")
        case .pinned: L10n.tr("clipboard.filter.pinned")
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .screenshots: "photo"
        case .pinned: "pin.fill"
        }
    }
}

private final class ClipboardPaneState: ObservableObject {
    @Published var query = ""
    @Published var filter: ClipboardFilter = .all
    @Published var copiedID: String?
    @Published var controlsCompact = false

    func updateScrollOffset(_ offset: CGFloat) {
        if !controlsCompact, offset > 18 {
            controlsCompact = true
        } else if controlsCompact, offset < 5 {
            controlsCompact = false
        }
    }
}

struct ClipboardPane: View {
    @ObservedObject var clipboard: ClipboardStore
    @StateObject private var state = ClipboardPaneState()

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var visibleItems: [ClipboardItem] {
        let filtered = clipboard.items.compactMap { item -> (item: ClipboardItem, score: Int)? in
            let matchesFilter: Bool = switch state.filter {
            case .all: true
            case .text: item.kind == .text
            case .screenshots: item.kind == .screenshot
            case .pinned: clipboard.pinnedIDs.contains(item.id)
            }
            guard matchesFilter else { return nil }
            guard !state.query.isEmpty else { return (item, 0) }
            guard let score = ClipboardSearchMatcher.score(
                query: state.query,
                candidate: item.searchableText
            ) else { return nil }
            return (item, score)
        }
        return filtered.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.item.createdAt > right.item.createdAt
        }.map(\.item)
    }

    var body: some View {
        let displayedItems = visibleItems
        VStack(spacing: 7) {
            controls

            if displayedItems.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(displayedItems) { item in
                            ClipboardShelfCard(
                                item: item,
                                pinned: clipboard.pinnedIDs.contains(item.id),
                                copied: state.copiedID == item.id,
                                copy: { copy(item) },
                                togglePin: { clipboard.togglePinned(item) },
                                remove: { clipboard.remove(item) },
                                open: {
                                    if let url = item.fileURL { NSWorkspace.shared.open(url) }
                                }
                            )
                        }
                    }
                    // Даёт последней, в том числе неполной, строке подняться над нижним краем.
                    .padding(.bottom, scrollRunway(for: displayedItems.count))
                    .background(ClipboardScrollObserver { state.updateScrollOffset($0) })
                }
            }
        }
        .padding(.horizontal, 12)
        .onDisappear { ThumbnailLoader.trimCache() }
    }

    private func scrollRunway(for itemCount: Int) -> CGFloat {
        itemCount >= 3 ? 88 : 14
    }

    private var controls: some View {
        VStack(spacing: state.controlsCompact ? 0 : 6) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                TextField(L10n.tr("clipboard.search"), text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                if state.controlsCompact {
                    compactFilterMenu
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                }
                if !state.query.isEmpty {
                    Button { state.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: state.controlsCompact ? 25 : 28)
            .hookyGlass(cornerRadius: 9, interactive: true)

            if !state.controlsCompact {
                expandedFilterRow
                    // Glass-композитор может продолжать рисовать слой с нулевой
                    // высотой. При сворачивании удаляем строку сразу из иерархии.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .animation(.easeInOut(duration: 0.20), value: state.controlsCompact)
    }

    private var expandedFilterRow: some View {
        HStack(spacing: 5) {
            ForEach(ClipboardFilter.allCases) { option in
                Button { state.filter = option } label: {
                    Label(option.title, systemImage: option.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .hookyGlass(
                            enabled: state.filter == option,
                            cornerRadius: 8,
                            interactive: true
                        )
                        .foregroundStyle(state.filter == option ? .white : .white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 24)
    }

    private var compactFilterMenu: some View {
        Menu {
            ForEach(ClipboardFilter.allCases) { option in
                Button { state.filter = option } label: {
                    Label(option.title, systemImage: option.symbol)
                }
            }
        } label: {
            Image(systemName: state.filter.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: state.query.isEmpty ? "rectangle.on.rectangle.slash" : "magnifyingglass")
                .font(.system(size: 20, weight: .light))
            Text(state.query.isEmpty ? L10n.tr("clipboard.empty") : L10n.tr("clipboard.noResults"))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ item: ClipboardItem) {
        guard clipboard.copy(item) else { return }
        withAnimation(.easeOut(duration: 0.16)) { state.copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if state.copiedID == item.id {
                withAnimation(.easeOut(duration: 0.16)) { state.copiedID = nil }
            }
        }
    }
}
