import SwiftUI

struct LiquidGlassTabBar: View {
    let selectedTab: MainTab
    let selectTab: (MainTab) -> Void
    let swipeTab: (TabSwipeDirection) -> Void
    let createNote: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            tabButton(.allNotes)
            tabButton(.favorites)
            composeButton
            tabButton(.utilities)
            tabButton(.settings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            tabBarBackground
        }
        .contentShape(RoundedRectangle(cornerRadius: NoteFlowDesign.radiusPill, style: .continuous))
        .gesture(tabSwipeGesture)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            NoteFlowHaptics.selection()
            selectTab(tab)
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(isSelected ? NoteFlowDesign.ink : NoteFlowDesign.mute)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background {
                    if isSelected {
                        selectedTabBackground
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var composeButton: some View {
        Button {
            NoteFlowHaptics.mediumImpact()
            createNote()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 23, weight: .bold))
                .frame(width: 50, height: 46)
                .background {
                    composeIconBackground
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("새 메모")
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 42,
                      abs(horizontal) > abs(vertical) * 1.35 else {
                    return
                }

                if horizontal < 0 {
                    swipeTab(.next)
                } else {
                    swipeTab(.previous)
                }
            }
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: NoteFlowDesign.radiusPill, style: .continuous)

        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape
                        .stroke(.white.opacity(0.24), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 14)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape
                        .fill(NoteFlowDesign.canvas.opacity(0.48))
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.42),
                            .white.opacity(0.12),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                )
                .overlay(
                    shape
                        .stroke(.white.opacity(0.42), lineWidth: 0.7)
                )
                .overlay(
                    shape
                        .stroke(NoteFlowDesign.hairlineSoft.opacity(0.65), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 12)
                .shadow(color: .white.opacity(0.48), radius: 10, x: 0, y: -2)
        }
    }

    @ViewBuilder
    private var selectedTabBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(NoteFlowDesign.ink.opacity(0.08))
                .glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(NoteFlowDesign.softCloud)
        }
    }

    @ViewBuilder
    private var composeIconBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(NoteFlowDesign.ink.opacity(0.92))
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
        } else {
            Capsule(style: .continuous)
                .fill(NoteFlowDesign.ink)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
    }
}

#Preview {
    LiquidGlassTabBar(selectedTab: .allNotes, selectTab: { _ in }, swipeTab: { _ in }, createNote: { })
        .padding()
}

enum TabSwipeDirection {
    case previous
    case next
}
