import Combine
import SwiftUI

private final class ClipboardCardState: ObservableObject {
    @Published var hovering = false
}

struct ClipboardShelfCard: View {
    let item: ClipboardItem
    let pinned: Bool
    let copied: Bool
    let copy: () -> Void
    let togglePin: () -> Void
    let remove: () -> Void
    let open: () -> Void

    @StateObject private var state = ClipboardCardState()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cardContent
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1))
                    .onEnded { gesture in
                        focused = true
                        switch gesture {
                        case .first:
                            if item.kind == .screenshot { open() } else { copy() }
                        case .second: copy()
                        }
                    })
            if state.hovering || focused || copied {
                actions
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 21, height: 21)
                    .background(.black.opacity(0.78), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.7))
                    .padding(7)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(Color.white.opacity(state.hovering ? 0.07 : 0.042))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(copied ? .green.opacity(0.5) : .white.opacity(focused ? 0.32 : state.hovering ? 0.18 : 0.085), lineWidth: 0.8))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.14)) { state.hovering = value }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) {
            guard item.kind == .screenshot else { return .ignored }
            open(); return .handled
        }
        .onKeyPress(.return) { copy(); return .handled }
        .help(L10n.tr(item.kind == .screenshot ? "clipboard.shelf.screenshotHint" : "clipboard.shelf.textHint"))
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: item.isLink ? "link" : item.isProbablyCode
                          ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                    Text(item.linkHost ?? L10n.tr(item.isProbablyCode ? "clipboard.shelf.code" : "clipboard.shelf.text")).lineLimit(1)
                    Spacer(minLength: pinned ? 24 : 0)
                }
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))

                Text(item.text ?? "")
                    .font(item.isProbablyCode
                          ? .system(size: 10.5, weight: .regular, design: .monospaced)
                          : .system(size: 11, weight: .regular))
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.87))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                HStack {
                    Text(item.sourceName).lineLimit(1)
                    Spacer()
                    if !state.hovering && !focused { Text(item.createdAt, style: .time) }
                }
                    .padding(.trailing, state.hovering || focused ? 88 : 0)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(12)

        case .screenshot:
            if let url = item.fileURL {
                ZStack(alignment: .bottomLeading) {
                    Color.black
                    AsyncThumbnail(url: url, size: CGSize(width: 360, height: 160), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 32)
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                        Text(item.createdAt, style: .time)
                    }
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .frame(height: 21)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(7)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if copied {
                actionIcon("checkmark", tint: .green, action: {})
            } else {
                actionIcon("doc.on.doc", action: copy)
                actionIcon(pinned ? "pin.fill" : "pin", tint: pinned ? .orange : .white, action: togglePin)
                Menu {
                    if item.kind == .screenshot {
                        Button(L10n.tr("clipboard.shelf.open"), systemImage: "arrow.up.right.square", action: open)
                        Divider()
                    }
                    Button(L10n.tr("clipboard.shelf.remove"), role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L10n.tr("clipboard.shelf.more"))
            }
        }
        .padding(3)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.7))
    }

    private func actionIcon(_ symbol: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 23, height: 23)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr(symbol == "doc.on.doc" ? "clipboard.copy" : symbol == "checkmark" ? "clipboard.shelf.copied" : "clipboard.shelf.pin"))
    }
}
