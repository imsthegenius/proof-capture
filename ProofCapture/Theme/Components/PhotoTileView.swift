import SwiftUI

struct PhotoTileView: View {
    let image: UIImage?
    let dateText: String
    let activePoseIndex: Int
    let onTap: (() -> Void)?

    init(
        image: UIImage?,
        dateText: String,
        activePoseIndex: Int,
        onTap: (() -> Void)? = nil
    ) {
        self.image = image
        self.dateText = dateText
        self.activePoseIndex = activePoseIndex
        self.onTap = onTap
    }

    var body: some View {
        interactiveTile
            .accessibilityLabel("Check-in from \(dateText)")
    }

    @ViewBuilder
    private var interactiveTile: some View {
        if let onTap {
            tile
                .onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
        } else {
            tile
        }
    }

    private var tile: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(ProofTheme.paperLo)
                        .overlay(
                            Text("No photo")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ProofTheme.inkSoft)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(120 / 213, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))

            VStack(spacing: 6) {
                DateOverlayPill(text: dateText)
                PoseDots(activeIndex: activePoseIndex)
            }
            .padding(.bottom, 8)
        }
        .contentShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
    }
}
