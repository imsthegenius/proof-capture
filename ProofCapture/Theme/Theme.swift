import SwiftUI
import UIKit

enum ProofTheme {
    // MARK: - Colors (warm near-black base)
    static let background = Color(red: 12/255, green: 11/255, blue: 9/255)        // #0C0B09
    static let surface = Color(red: 28/255, green: 27/255, blue: 25/255)          // #1C1B19
    static let elevated = Color(red: 46/255, green: 44/255, blue: 42/255)         // #2E2C2A
    static let separator = Color(red: 28/255, green: 27/255, blue: 25/255)        // #1C1B19

    static let textPrimary = Color(red: 245/255, green: 242/255, blue: 237/255)   // #F5F2ED
    static let textSecondary = Color(red: 142/255, green: 138/255, blue: 130/255) // #8E8A82
    static let textTertiary = Color(red: 105/255, green: 100/255, blue: 94/255)   // #69645E

    static let accent = Color(red: 250/255, green: 250/255, blue: 252/255)        // #FAFAFC (cool white)

    // Camera overlays — need high contrast on camera feed
    // Glass effects available on iOS 26+, use overlayPill as fallback
    static let overlayPill = Color.black.opacity(0.65)
    static let overlayText = Color.white

    // Status indicators
    static let statusGood = Color(red: 106/255, green: 190/255, blue: 110/255)    // #6ABE6E
    static let statusFair = Color(red: 220/255, green: 190/255, blue: 140/255)    // #DCBE8C
    static let statusPoor = Color(red: 210/255, green: 90/255, blue: 85/255)      // #D25A55

    // MARK: - Spacing (4pt grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Corner Radius
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 20

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
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .modifier(PrimaryButtonBackground())
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }

    struct ProofSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .modifier(SecondaryButtonBackground())
                .opacity(configuration.isPressed ? 0.8 : 1.0)
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
