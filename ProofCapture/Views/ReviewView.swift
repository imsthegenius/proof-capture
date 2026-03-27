import SwiftUI

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss

    private let poseImages: [Pose: UIImage]
    @State private var isSaving = false
    @State private var savedSuccessfully = false

    init(images: [Pose: UIImage]) {
        self.poseImages = images
    }

    init(session: PhotoSession) {
        var images: [Pose: UIImage] = [:]
        for pose in Pose.allCases {
            if let photo = session.photo(for: pose) {
                images[pose] = photo
            }
        }
        self.poseImages = images
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Session Complete")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)
                .padding(.top, ProofTheme.spacingXL)

            Spacer()
                .frame(height: ProofTheme.spacingXL)

            photoGrid

            Spacer()

            bottomButtons
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, ProofTheme.spacingLG)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var photoGrid: some View {
        let photoWidth = (UIScreen.main.bounds.width - 64) / 3

        return HStack(spacing: ProofTheme.spacingMD) {
            ForEach(Pose.allCases) { pose in
                VStack(spacing: ProofTheme.spacingSM) {
                    if let image = poseImages[pose] {
                        NavigationLink(destination: FullPhotoView(image: image, title: "\(pose.title) progress photo")) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: photoWidth, height: photoWidth * 1.45)
                                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                                .accessibilityLabel("\(pose.title) progress photo")
                        }
                    } else {
                        RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                            .fill(ProofTheme.surface)
                            .frame(width: photoWidth, height: photoWidth * 1.45)
                            .overlay(
                                Text("—")
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundStyle(ProofTheme.textTertiary)
                            )
                    }

                    Text(pose.title)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, ProofTheme.spacingLG)
    }

    private var bottomButtons: some View {
        VStack(spacing: ProofTheme.spacingSM) {
            Button {
                Task { await saveToCamera() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(ProofTheme.background)
                    } else if savedSuccessfully {
                        Text("Saved")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(ProofTheme.background)
                    } else {
                        Text("Save to Camera Roll")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(ProofTheme.background)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(savedSuccessfully ? ProofTheme.statusGood : ProofTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .disabled(isSaving || savedSuccessfully)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .padding(.top, ProofTheme.spacingSM)
        }
    }

    private func saveToCamera() async {
        isSaving = true
        let manager = CameraManager()

        for pose in Pose.allCases {
            if let image = poseImages[pose] {
                _ = await manager.saveToPhotoLibrary(image)
            }
        }

        isSaving = false
        savedSuccessfully = true
    }
}

#Preview {
    ReviewView(images: [:])
        .preferredColorScheme(.dark)
}
