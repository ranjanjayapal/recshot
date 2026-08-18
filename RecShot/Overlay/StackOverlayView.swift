import SwiftUI

struct StackOverlayView: View {
    @EnvironmentObject private var state: AppState

    private var showingStack: Bool {
        state.isStackExpanded && !state.items.isEmpty
    }

    private var maxStackHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.55
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showingStack {
                expandedStack
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            } else if !state.items.isEmpty {
                peekPile
                    .onTapGesture { state.toggleStack() }
                    .transition(.opacity)
            }

            controlPill
        }
        .padding(10)
        .fixedSize()
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showingStack)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.items.count)
        .background(SizeProbe())
    }

    private var controlPill: some View {
        HStack(spacing: 10) {
            pillButton(systemImage: "camera.viewfinder", help: "Capture region (⌥⌘S)") {
                state.captureRegion()
            }

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 18)

            HStack(spacing: 6) {
                Image(systemName: "square.stack")
                    .font(.system(size: 13, weight: .semibold))
                if !state.items.isEmpty {
                    Text("\(state.items.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Image(systemName: showingStack ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .onTapGesture {
                guard !state.items.isEmpty else { return }
                state.toggleStack()
            }
            .opacity(state.items.isEmpty ? 0.4 : 1)
            .help(showingStack ? "Hide screenshot stack" : "Show screenshot stack")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
    }

    private func pillButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.recCoral)
            .frame(width: 28, height: 28)
            .background(Color.recCoral.opacity(0.16), in: Circle())
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .help(help)
    }

    private var peekPile: some View {
        let peek = Array(state.items.prefix(3))
        return ZStack {
            ForEach(Array(peek.reversed().enumerated()), id: \.element.id) { index, item in
                let layer = peek.count - 1 - index
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 78, height: 52)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
                    .rotationEffect(.degrees(Double(layer) * 5 - 4))
                    .offset(x: CGFloat(layer) * 7, y: CGFloat(layer) * 5)
            }
        }
        .frame(width: 110, height: 68, alignment: .bottomLeading)
        .padding(.leading, 6)
        .help("Show screenshot stack")
    }

    private var expandedStack: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: state.items.count > 5) {
                VStack(spacing: 8) {
                    ForEach(Array(state.items.reversed())) { item in
                        ThumbnailCard(item: item)
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .frame(width: 156)
            .frame(maxHeight: maxStackHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            .onAppear {
                if let id = state.items.first?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: state.items.first?.id) { _, id in
                if let id {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct SizeProbe: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { report(geometry.size) }
                .onChange(of: geometry.size) { _, size in report(size) }
        }
    }

    private func report(_ size: CGSize) {
        OverlayPanelController.shared.resize(
            to: NSSize(width: size.width, height: size.height)
        )
    }
}
