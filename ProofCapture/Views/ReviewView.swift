import SwiftUI
import Photos

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let poseImages: [Pose: UIImage]
    private let session: PhotoSession?
    private let isFromHistory: Bool
    @State private var isSaving = false
    @State private var savedSuccessfully = false
    @State private var showDeleteConfirmation = false

    // After capture — no session reference, shows "Session Complete"
    init(images: [Pose: UIImage]) {
        self.poseImages = images
        self.session = nil
        self.isFromHistory = false
    }

    // From history — has session reference, shows date and delete option
    init(session: PhotoSession) {
        var images: [Pose: UIImage] = [:]
        for pose in Pose.allCases {
            if let photo = session.photo(for: pose) {
                images[pose] = photo
            }
        }
        self.poseImages = images
        self.session = session
        self.isFromHistory = true
    }

    private var titleText: String {
        if isFromHistory, let session {
            return session.date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "Session Complete"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(titleText)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)
                .padding(.top, ProofTheme.spacingXL)
                .accessibilityAddTraits(.isHeader)

            Spacer()
                .frame(height: ProofTheme.spacingLG)

            photoGrid

            Spacer()

            bottomButtons
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, ProofTheme.spacingLG)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session and its photos will be permanently deleted.")
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        GeometryReader { geometry in
            let interItemSpacing: CGFloat = ProofTheme.spacingSM
            let totalSpacing = (ProofTheme.spacingMD * 2) + (interItemSpacing * 2)
            let photoWidth = (geometry.size.width - totalSpacing) / 3

            HStack(spacing: interItemSpacing) {
                ForEach(Pose.allCases) { pose in
                    VStack(spacing: ProofTheme.spacingSM) {
                        if let image = poseImages[pose] {
                            NavigationLink(destination: FullPhotoView(image: image, title: "\(pose.title) progress photo")) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: photoWidth, height: photoWidth * 1.6)
                                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                                    .accessibilityLabel("\(pose.title) progress photo, tap to view full screen")
                            }
                        } else {
                            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                                .fill(ProofTheme.surface)
                                .frame(width: photoWidth, height: photoWidth * 1.6)
                            .overlay(
                                Text("--")
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundStyle(ProofTheme.textTertiary)
                            )
                            .accessibilityLabel("\(pose.title) photo not taken")
                    }

                    Text(pose.title)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
            }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: ProofTheme.spacingSM) {
            if !isFromHistory {
                // Save to camera roll — only after capture
                Button {
                    Task { await saveToCamera() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else if savedSuccessfully {
                            Text("Saved")
                        } else {
                            Text("Save to Camera Roll")
                        }
                    }
                }
                .buttonStyle(ProofTheme.ProofButtonStyle())
                .disabled(isSaving || savedSuccessfully)
                .accessibilityLabel(isSaving ? "Saving photos" : savedSuccessfully ? "Photos saved" : "Save photos to camera roll")
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .frame(height: 44)
            }
            .accessibilityLabel("Close review")
            .padding(.top, ProofTheme.spacingXS)

            if isFromHistory {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete Session")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.statusPoor)
                        .frame(height: 44)
                }
                .accessibilityLabel("Delete this session")
                .padding(.top, ProofTheme.spacingXS)
            }
        }
    }

    // MARK: - Actions

    private func saveToCamera() async {
        isSaving = true

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSaving = false
            return
        }

        for pose in Pose.allCases {
            if let image = poseImages[pose] {
                try? await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
        }

        isSaving = false
        savedSuccessfully = true
    }

    private func deleteSession() {
        guard let session else { return }
        modelContext.delete(session)
        dismiss()
    }
}

#Preview {
    ReviewView(images: [:])
        .preferredColorScheme(.dark)
}
