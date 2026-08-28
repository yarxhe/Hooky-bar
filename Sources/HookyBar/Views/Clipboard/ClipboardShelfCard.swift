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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
            if state.hovering || copied {
                actions
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            } else if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 21, height: 21)
                    .background(.black.opacity(0.78), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.7))
                    .padding(7)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(Color.white.opacity(state.hovering ? 0.07 : 0.042))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(state.hovering ? Color.white.opacity(0.18) : .white.opacity(0.085), lineWidth: 0.8))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.14)) { state.hovering = value }
        }
        .onTapGesture(perform: copy)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: item.isLink ? "link" : item.isProbablyCode
                          ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                    Text(item.sourceName).lineLimit(1)
                    Spacer(minLength: 40)
                }
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))

                Text(item.text ?? "")
                    .font(item.isProbablyCode
                          ? .system(size: 10, weight: .medium, design: .monospaced)
                          : .system(size: 10.5, weight: .medium))
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.87))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                Text(item.createdAt, style: .time)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(9)

        case .screenshot:
            if let url = item.fileURL {
                ZStack(alignment: .bottomLeading) {
                    Color.black
                    AsyncThumbnail(url: url, size: CGSize(width: 360, height: 184), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(3)
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
                if item.kind == .screenshot {
                    actionIcon("arrow.up.left.and.arrow.down.right", action: open)
                }
                actionIcon(pinned ? "pin.fill" : "pin", tint: pinned ? .orange : .white, action: togglePin)
                actionIcon("trash", tint: .red, action: remove)
                actionIcon("doc.on.doc", action: copy)
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
    }
}
