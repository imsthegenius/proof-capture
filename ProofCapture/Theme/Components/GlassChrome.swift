import SwiftUI

// Liquid Glass chrome — the v12 material. Every capsule, pill, and button
// routes through LiquidGlassCapsule so the stack stays consistent. See
// .claude/rules/design-system-v12.md for the layer recipe.

enum LiquidGlassVariant {
    case paperDark   // on photo/dark canvas (auth splash, camera chrome)
    case paperLight  // on paper canvas (tab bar over Albums, date pills over grid)
}

struct LiquidGlassCapsule: ViewModifier {
    let variant: LiquidGlassVariant

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(fallback)
        }
    }

    @ViewBuilder
    private var fallback: some View {
        switch variant {
        case .paperDark:
            Capsule()
                .fill(Color.white.opacity(0.22))
                .overlay(Capsule().fill(ProofTheme.warmBeige.opacity(0.18)))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 40, y: 8)
        case .paperLight:
            Capsule()
                .fill(Color(red: 250/255, green: 250/255, blue: 250/255).opacity(0.7))
                .overlay(Capsule().stroke(ProofTheme.inkSoft.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 4)
        }
    }
}

extension View {
    func liquidGlassCapsule(_ variant: LiquidGlassVariant = .paperDark) -> some View {
        modifier(LiquidGlassCapsule(variant: variant))
    }
}

// Primary CTA button matching auth frame 336:236.
// 64pt height, capsule, SF Pro Medium 17pt label.
struct LiquidGlassButton<Label: View>: View {
    let action: () -> Void
    let variant: LiquidGlassVariant
    @ViewBuilder let label: () -> Label

    init(
        variant: LiquidGlassVariant = .paperDark,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .padding(.horizontal, 20)
        }
        .buttonStyle(PressScaleStyle())
        .liquidGlassCapsule(variant)
    }

    private var foreground: Color {
        variant == .paperDark ? .white : ProofTheme.inkPrimary
    }
}

// Month picker / trailing-chevron pill matching Albums frame 379:1360.
// 27pt height, 12/10 padding, Medium 17pt.
struct DatePill: View {
    let label: String
    let variant: LiquidGlassVariant

    init(_ label: String, variant: LiquidGlassVariant = .paperLight) {
        self.label = label
        self.variant = variant
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 27)
        .liquidGlassCapsule(variant)
    }

    private var foreground: Color {
        variant == .paperDark ? .white : ProofTheme.inkPrimary
    }
}

// Small translucent-on-image caption pill for photo tiles.
// 21pt height, SF Pro Regular 10pt, white text.
struct DateOverlayPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.01))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            )
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: ProofTheme.animationFast), value: configuration.isPressed)
    }
}

#Preview("LiquidGlassButton — paperDark") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            LiquidGlassButton(action: {}) { Text("Sign Up") }
            LiquidGlassButton(action: {}) { Text("Sign In With Apple") }
        }
        .padding(.horizontal, 13)
    }
}

#Preview("DatePill & DateOverlayPill") {
    ZStack {
        ProofTheme.paperHi.ignoresSafeArea()
        VStack(spacing: 20) {
            DatePill("April")
            DatePill("April", variant: .paperDark)
                .background(Color.gray)
            DateOverlayPill(label: "16th April")
                .padding()
                .background(Color.gray)
        }
    }
}
