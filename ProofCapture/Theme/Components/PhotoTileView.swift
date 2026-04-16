import SwiftUI

// Album thumbnail matching Albums frame 379:1360. 120x213 aspect,
// image fills, DateOverlayPill + PoseDots pinned to bottom.

struct PhotoTileView<Image: View>: View {
    let dateLabel: String
    let poseCount: Int
    let currentPose: Int
    @ViewBuilder let image: () -> Image

    init(
        dateLabel: String,
        poseCount: Int = 3,
        currentPose: Int = 0,
        @ViewBuilder image: @escaping () -> Image
    ) {
        self.dateLabel = dateLabel
        self.poseCount = poseCount
        self.currentPose = currentPose
        self.image = image
    }

    var body: some View {
        image()
            .aspectRatio(120/213, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    DateOverlayPill(label: dateLabel)
                    PoseDots(count: poseCount, current: currentPose)
                }
                .padding(.bottom, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM, style: .continuous))
    }
}

// 3-dot indicator for pose progression within a check-in.
struct PoseDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(ProofTheme.inkPrimary)
                    .opacity(idx == current ? 1 : 0.3)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityLabel("Pose \(current + 1) of \(count)")
    }
}

#Preview("PhotoTileView grid") {
    ZStack {
        ProofTheme.paperHi.ignoresSafeArea()
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
            spacing: 4
        ) {
            ForEach(0..<6, id: \.self) { _ in
                PhotoTileView(dateLabel: "16th April") {
                    Color.gray
                }
            }
        }
        .padding(.horizontal, 17)
    }
}
