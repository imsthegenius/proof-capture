import SwiftUI

struct ComparisonView: View {
    let sessionA: PhotoSession
    let sessionB: PhotoSession
    @State private var selectedPose: Pose = .front

    var body: some View {
        VStack(spacing: 0) {
            // Pose picker
            HStack(spacing: 0) {
                ForEach(Pose.allCases) { pose in
                    Button {
                        selectedPose = pose
                    } label: {
                        Text(pose.title)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(selectedPose == pose ? ProofTheme.textPrimary : ProofTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)

            // Side by side
            HStack(spacing: 2) {
                photoColumn(session: sessionA, pose: selectedPose)
                photoColumn(session: sessionB, pose: selectedPose)
            }
            .frame(maxHeight: .infinity)

            // Date labels
            HStack {
                Text(sessionA.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .frame(maxWidth: .infinity)

                Text(sessionB.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, ProofTheme.spacingSM)
        }
        .background(ProofTheme.background)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func photoColumn(session: PhotoSession, pose: Pose) -> some View {
        Group {
            if let image = session.photo(for: pose) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(ProofTheme.surface)
                    .overlay(
                        Text("No photo")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
            }
        }
    }
}
