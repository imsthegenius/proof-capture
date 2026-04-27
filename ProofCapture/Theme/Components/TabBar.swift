import SwiftUI

enum LiquidGlassTab: Hashable, CaseIterable {
    case camera
    case album

    var glyph: String {
        switch self {
        case .camera: return "◉"
        case .album: return "▦"
        }
    }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .album: return "Album"
        }
    }
}

struct LiquidGlassTabBar: View {
    @Binding var selection: LiquidGlassTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LiquidGlassTab.allCases, id: \.self) { tab in
                Button {
                    ProofTheme.hapticLight()
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Text(tab.glyph)
                            .font(.system(size: 32, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? ProofTheme.inkPrimary : ProofTheme.inkSoft)
                    .frame(width: 102)
                    .padding(.vertical, 8)
                    .background(selection == tab ? ProofTheme.pillFillLight : Color.clear, in: .capsule)
                }
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(8)
        .liquidGlassCapsule(.paperLight)
    }
}

struct PoseDots: View {
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == activeIndex ? 1.0 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Pose \(activeIndex + 1) of 3")
    }
}
