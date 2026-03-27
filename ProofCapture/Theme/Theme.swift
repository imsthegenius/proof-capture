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
    static let textTertiary = Color(red: 82/255, green: 78/255, blue: 72/255)     // #524E48

    static let accent = Color(red: 235/255, green: 235/255, blue: 230/255)        // #EBEBE6 (warm white)

    // Camera overlays — need high contrast on camera feed
    static let overlayPill = Color.black.opacity(0.65)
    static let overlayText = Color.white

    // Status indicators
    static let statusGood = Color(red: 106/255, green: 190/255, blue: 110/255)    // #6ABE6E
    static let statusFair = Color(red: 230/255, green: 180/255, blue: 80/255)     // #E6B450
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
}
