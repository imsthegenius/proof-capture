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
    @State private var showSaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var hasAppeared = false
    @State private var savePulse = false

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
            titleSection

            Spacer()
                .frame(height: ProofTheme.spacingLG)

            photoGrid
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)
                .animation(.easeOut(duration: 0.45).delay(0.08), value: hasAppeared)

            Spacer()

            bottomButtons
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, ProofTheme.spacingLG)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)
                .animation(.easeOut(duration: 0.45).delay(0.16), value: hasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proofDynamicType()
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
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        Text(titleText)
            .proofFont(24, weight: .light, relativeTo: .title2)
            .foregroundStyle(ProofTheme.textPrimary)
            .padding(.top, ProofTheme.spacingXL)
            .accessibilityAddTraits(.isHeader)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .animation(.easeOut(duration: 0.45), value: hasAppeared)
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        GeometryReader { geometry in
            let interItemSpacing: CGFloat = ProofTheme.spacingSM
            let totalSpacing = (ProofTheme.spacingMD * 2) + (interItemSpacing * 2)
            let photoWidth = max(0, (geometry.size.width - totalSpacing) / 3)

            HStack(spacing: interItemSpacing) {
                ForEach(Array(Pose.allCases.enumerated()), id: \.offset) { index, pose in
                    photoCell(for: pose, width: photoWidth)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 18)
                        .scaleEffect(hasAppeared ? 1 : 0.97)
                        .animation(.easeOut(duration: 0.45).delay(0.08 + (0.06 * Double(index))), value: hasAppeared)
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func photoCell(for pose: Pose, width: CGFloat) -> some View {
        VStack(spacing: ProofTheme.spacingSM) {
            if let image = poseImages[pose] {
                NavigationLink(destination: FullPhotoView(image: image, title: "\(pose.title) progress photo")) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: width * 1.6)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                        .accessibilityLabel("\(pose.title) progress photo, tap to view full screen")
                }
            } else {
                RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                    .fill(ProofTheme.surface)
                    .frame(width: width, height: width * 1.6)
                    .overlay(
                        Text("--")
                            .proofFont(15, weight: .light, relativeTo: .body)
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
                    .accessibilityLabel("\(pose.title) photo not taken")
            }

            Text(pose.title)
                .proofFont(12, weight: .light, relativeTo: .caption1)
                .foregroundStyle(ProofTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: ProofTheme.spacingSM) {
            if !isFromHistory {
                if showSaveConfirmation {
                    saveConfirmationBanner
                }

                if isSaving {
                    Text("Saving\u{2026}")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .modifier(ProofTheme.PrimaryButtonBackground())
                        .opacity(savePulse ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: savePulse)
                        .onAppear { savePulse = true }
                        .onDisappear { savePulse = false }
                        .accessibilityLabel("Saving photos")
                } else if savedSuccessfully {
                    savedStateBadge
                } else {
                    Button {
                        Task { await saveToCamera() }
                    } label: {
                        Text("Save to Camera Roll")
                    }
                    .buttonStyle(ProofTheme.ProofButtonStyle())
                    .accessibilityLabel("Save photos to camera roll")
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .proofFont(15, weight: .light, relativeTo: .body)
                    .foregroundStyle(ProofTheme.textSecondary)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Close review")
            .padding(.top, ProofTheme.spacingXS)

            if isFromHistory {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete Session")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.statusPoor)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Delete this session")
                .padding(.top, ProofTheme.spacingXS)
            }
        }
    }

    private var savedStateBadge: some View {
        HStack(spacing: ProofTheme.spacingSM) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(ProofTheme.statusGood)

            Text("Saved to Camera Roll")
                .proofFont(15, weight: .light, relativeTo: .body)
                .foregroundStyle(ProofTheme.statusGood)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .background(ProofTheme.statusGood.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                .stroke(ProofTheme.statusGood.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
        .accessibilityLabel("Photos saved to camera roll")
    }

    private var saveConfirmationBanner: some View {
        HStack(spacing: ProofTheme.spacingSM) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.statusGood)

            Text("Saved to Photos")
                .proofFont(13, weight: .light, relativeTo: .footnote)
                .foregroundStyle(ProofTheme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, ProofTheme.spacingMD)
        .padding(.vertical, ProofTheme.spacingSM)
        .frame(maxWidth: .infinity)
        .background(ProofTheme.surface.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke(ProofTheme.statusGood.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel("Saved successfully")
    }

    // MARK: - Actions

    private func saveToCamera() async {
        await MainActor.run {
            isSaving = true
            showSaveConfirmation = false
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            await MainActor.run {
                isSaving = false
            }
            return
        }

        do {
            for pose in Pose.allCases {
                if let image = poseImages[pose] {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
            }

            await MainActor.run {
                isSaving = false
                savedSuccessfully = true
                showSaveConfirmation = true
            }
            ProofTheme.hapticSuccess()

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1400))
                guard showSaveConfirmation else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    showSaveConfirmation = false
                }
            }
        } catch {
            await MainActor.run {
                isSaving = false
            }
        }
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
