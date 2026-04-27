import SwiftUI

enum LiquidGlassVariant: Equatable {
    case paperDark
    case paperLight
}

extension View {
    func liquidGlassCapsule(_ variant: LiquidGlassVariant = .paperDark) -> some View {
        modifier(LiquidGlassCapsuleModifier(variant: variant))
    }
}

private struct LiquidGlassCapsuleModifier: ViewModifier {
    let variant: LiquidGlassVariant

    func body(content: Content) -> some View {
        let foregroundFill = variant == .paperDark
            ? ProofTheme.warmBeige.opacity(0.70)
            : Color.white.opacity(0.70)

        if #available(iOS 26, *) {
            content
                .background(foregroundFill, in: .capsule)
                .glassEffect(variant == .paperDark ? .regular.interactive() : .regular, in: .capsule)
                .shadow(color: Color.black.opacity(0.12), radius: 40, x: 0, y: 8)
        } else {
            content
                .background(foregroundFill)
                .background(.ultraThinMaterial, in: .capsule)
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(variant == .paperDark ? 0.28 : 0.18), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 40, x: 0, y: 8)
        }
    }
}

struct LiquidGlassButton<Label: View>: View {
    let variant: LiquidGlassVariant
    let action: () -> Void
    let label: Label

    init(
        variant: LiquidGlassVariant = .paperDark,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.variant = variant
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(variant == .paperDark ? ProofTheme.paperHi : ProofTheme.inkPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
        .liquidGlassCapsule(variant)
    }
}

struct DatePill: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(ProofTheme.inkPrimary)
            .padding(.horizontal, 12)
            .frame(height: 27)
        }
        .liquidGlassCapsule(.paperLight)
        .accessibilityLabel("\(text) filter")
    }
}

struct DateOverlayPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(Color.white.opacity(0.10), in: .capsule)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(
                Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.5)
            )
    }
}
