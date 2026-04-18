import SwiftUI
import UIKit

enum ProofTheme {
    // MARK: - Colors (warm near-black base)
    static let background = Color(red: 12/255, green: 11/255, blue: 9/255)        // #0C0B09
    static let surface = Color(red: 28/255, green: 27/255, blue: 25/255)          // #1C1B19
    static let elevated = Color(red: 46/255, green: 44/255, blue: 42/255)         // #2E2C2A
    static let separator = Color(red: 28/255, green: 27/255, blue: 25/255)        // #1C1B19

    static let textPrimary = Color(red: 245/255, green: 242/255, blue: 237/255)   // #F5F2ED
    static let textSecondary = Color(red: 168/255, green: 163/255, blue: 155/255) // #A8A39B
    static let textTertiary = Color(red: 130/255, green: 125/255, blue: 118/255)  // #827D76

    static let accent = Color(red: 235/255, green: 235/255, blue: 230/255)        // #EBEBE6 (warm white)

    // MARK: - Light Surface Tokens (Albums tab — paper aesthetic)
    // Camera flow stays dark (camera feed dominates). Albums is the only light surface.
    static let paperHi = Color(red: 255/255, green: 248/255, blue: 237/255)       // #FFF8ED — warm cream
    static let paperLo = Color(red: 245/255, green: 234/255, blue: 217/255)       // #F5EAD9 — slight tint for gradient
    static let inkPrimary = Color(red: 49/255, green: 64/255, blue: 77/255)       // #31404D — slate text on paper
    static let inkSoft = Color(red: 92/255, green: 71/255, blue: 61/255)          // #5C473D — warm brown secondary
    static let pillFillLight = Color(red: 237/255, green: 237/255, blue: 237/255) // #EDEDED — selected tab pill on light
    static let pillFillDark = Color(red: 84/255, green: 99/255, blue: 109/255)    // #54636D — selected pill on light, alt
    static let warmBeige = Color(red: 245/255, green: 237/255, blue: 224/255)     // #F5EDE0 — liquid glass tint (never a foreground)

    // MARK: - Animation Timing
    static let animationFast: Double = 0.15
    static let animationDefault: Double = 0.3
    static let animationSlow: Double = 0.5
    static let animationEntrance: Double = 0.6
    static let staggerShort: Double = 0.05
    static let staggerDefault: Double = 0.12
    static let staggerLong: Double = 0.2

    // Camera overlays — need high contrast on camera feed
    // Glass effects available on iOS 26+, use overlayPill as fallback
    static let overlayScrimLight = Color.black.opacity(0.4)
    static let overlayScrim = Color.black.opacity(0.5)
    static let overlayPill = Color.black.opacity(0.65)
    static let overlayText = Color.white

    // Status indicators
    static let statusGood = Color(red: 106/255, green: 190/255, blue: 110/255)    // #6ABE6E
    static let statusFair = Color(red: 220/255, green: 190/255, blue: 140/255)    // #DCBE8C
    static let statusPoor = Color(red: 210/255, green: 90/255, blue: 85/255)      // #D25A55

    // MARK: - Border Glow (banking KYC-style readiness indicator)
    // Full-screen edge glow visible from 2 meters — replaces small status ring
    static let borderNeutral = Color.white.opacity(0.3)                            // Body detected, adjusting
    static let borderAlmost = Color(red: 220/255, green: 190/255, blue: 140/255)  // 1-2 checks failing
    static let borderReady = Color(red: 106/255, green: 190/255, blue: 110/255)   // All checks pass → capture

    static let borderWidthNeutral: CGFloat = 2
    static let borderWidthAlmost: CGFloat = 3
    static let borderWidthReady: CGFloat = 4

    // MARK: - Spacing (4pt grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Dynamic Type
    static let dynamicTypeRange: ClosedRange<DynamicTypeSize> = .xSmall ... .xxxLarge

    static func scaledFontSize(
        _ baseSize: CGFloat,
        relativeTo textStyle: UIFont.TextStyle = .body,
        maximumScaleFactor: CGFloat = 1.35
    ) -> CGFloat {
        let scaledSize = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: baseSize)
        return min(scaledSize, baseSize * maximumScaleFactor)
    }

    // MARK: - Corner Radius
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 20
    static let radiusCapsule: CGFloat = 1000          // liquid-glass capsules (buttons, pills, tab bar)
    static let cameraFrameRadius: CGFloat = 24        // inner rounded-rect camera frame (Figma Subtract curvature)

    // MARK: - Haptics
    static func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Button Styles

    struct ProofButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: ProofTheme.scaledFontSize(15, relativeTo: .body), weight: .regular))
                .dynamicTypeSize(ProofTheme.dynamicTypeRange)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .modifier(PrimaryButtonBackground())
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .animation(.easeOut(duration: ProofTheme.animationFast), value: configuration.isPressed)
        }
    }

    struct ProofSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: ProofTheme.scaledFontSize(15, relativeTo: .body), weight: .regular))
                .dynamicTypeSize(ProofTheme.dynamicTypeRange)
                .foregroundStyle(ProofTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .modifier(SecondaryButtonBackground())
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .animation(.easeOut(duration: ProofTheme.animationFast), value: configuration.isPressed)
        }
    }

    // Background modifiers with iOS 26 glass / iOS 17 fallback
    struct PrimaryButtonBackground: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26, *) {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content
                    .background(ProofTheme.accent)
                    .clipShape(.capsule)
            }
        }
    }

    struct SecondaryButtonBackground: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content
                    .background(ProofTheme.surface)
                    .clipShape(.capsule)
            }
        }
    }
}

extension View {
    func proofDynamicType() -> some View {
        dynamicTypeSize(ProofTheme.dynamicTypeRange)
    }

    func proofFont(
        _ baseSize: CGFloat,
        weight: Font.Weight,
        relativeTo textStyle: UIFont.TextStyle = .body,
        maximumScaleFactor: CGFloat = 1.35
    ) -> some View {
        font(.system(
            size: ProofTheme.scaledFontSize(baseSize, relativeTo: textStyle, maximumScaleFactor: maximumScaleFactor),
            weight: weight
        ))
    }
}
