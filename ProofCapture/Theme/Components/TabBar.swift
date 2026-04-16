import SwiftUI

// Bottom tab bar matching Albums frame 379:1360. Two-tab — Camera and Album.
// Glyphs are unicode (◉ ▦) inside SF Pro Semibold, not SF Symbols.

enum CheckdTab: String, CaseIterable, Identifiable {
    case camera, album
    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .camera: return "\u{25C9}" // ◉
        case .album:  return "\u{25A6}" // ▦
        }
    }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .album:  return "Album"
        }
    }
}

struct LiquidGlassTabBar: View {
    @Binding var selection: CheckdTab
    var tabs: [CheckdTab] = CheckdTab.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabBarItem(
                    tab: tab,
                    isSelected: selection == tab,
                    onTap: {
                        ProofTheme.hapticLight()
                        selection = tab
                    }
                )
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .liquidGlassCapsule(.paperLight)
        .padding(.horizontal, ProofTheme.spacingLG)
        .padding(.bottom, 25)
        .padding(.top, 16)
    }
}

private struct TabBarItem: View {
    let tab: CheckdTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0.5) {
                Text(tab.glyph)
                    .font(.system(size: 32, weight: .semibold))
                Text(tab.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 8)
            .background(background)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        isSelected ? ProofTheme.paperHi : ProofTheme.inkSoft
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Capsule().fill(ProofTheme.pillFillDark)
        } else {
            Color.clear
        }
    }
}

#Preview("LiquidGlassTabBar") {
    ZStack {
        ProofTheme.paperHi.ignoresSafeArea()
        VStack {
            Spacer()
            LiquidGlassTabBar(selection: .constant(.album))
        }
    }
}
