import Photos
import SwiftUI

/// Review screen — cream paper world. Shown after a session completes (full review)
/// and when tapping a session from Albums. Three pose photos as a hero card grid,
/// session date as the title, glass action capsules at the bottom.
struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let poseImages: [Pose: UIImage]
    private let qualityReports: [Pose: PhotoQualityGate.Report]
    private let session: PhotoSession?
    private let isFromHistory: Bool
    private let onRetake: ((Pose) -> Void)?
    @State private var isSaving = false
    @State private var savedSuccessfully = false
    @State private var showDeleteConfirmation = false
    @State private var hasAppeared = false

    init(
        images: [Pose: UIImage],
        qualityReports: [Pose: PhotoQualityGate.Report] = [:],
        onRetake: ((Pose) -> Void)? = nil
    ) {
        self.poseImages = images
        self.qualityReports = qualityReports
        self.session = nil
        self.isFromHistory = false
        self.onRetake = onRetake
    }

    init(session: PhotoSession) {
        var images: [Pose: UIImage] = [:]
        for pose in Pose.allCases {
            if let photo = session.photo(for: pose) {
                images[pose] = photo
            }
        }
        self.poseImages = images
        self.qualityReports = [:]
        self.session = session
        self.isFromHistory = true
        self.onRetake = nil
    }

    private var titleText: String {
        if isFromHistory, let session {
            return session.date.formatted(.dateTime.day().month(.wide))
        }
        return "Saved in Checkd"
    }

    private var eyebrowText: String {
        if isFromHistory {
            return "ALBUM ENTRY"
        }
        return "TODAY"
    }

    private var qualityIssues: [(pose: Pose, issue: String)] {
        Pose.allCases.flatMap { pose in
            (qualityReports[pose]?.issues ?? []).map { (pose: pose, issue: $0) }
        }
    }

    var body: some View {
        ZStack {
            paperBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: ProofTheme.spacingLG) {
                header
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.top, ProofTheme.spacingMD)

                photoGrid
                    .padding(.horizontal, ProofTheme.spacingMD)

                if !qualityIssues.isEmpty {
                    qualityNotes
                        .padding(.horizontal, ProofTheme.spacingMD)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                actions
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.bottom, ProofTheme.spacingLG)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete session", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session and its photos will be permanently deleted.")
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
        }
        .proofDynamicType()
    }

    private var paperBackground: some View {
        LinearGradient(
            colors: [ProofTheme.paperHi, ProofTheme.paperLo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrowText)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(ProofTheme.inkSoft.opacity(0.7))

                Text(titleText)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(ProofTheme.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProofTheme.inkPrimary)
                    .frame(width: 36, height: 36)
                    .background(closeBackground)
            }
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var closeBackground: some View {
        if #available(iOS 26, *) {
            Circle().fill(.clear).glassEffect(.regular, in: .circle)
        } else {
            Circle().fill(ProofTheme.paperHi.opacity(0.6))
                .overlay(Circle().stroke(ProofTheme.inkSoft.opacity(0.1), lineWidth: 1))
        }
    }

    private var photoGrid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let cellWidth = (geo.size.width - spacing * 2) / 3
            let cellHeight = cellWidth * 1.6

            HStack(spacing: spacing) {
                ForEach(Pose.allCases) { pose in
                    photoCell(pose: pose, width: cellWidth, height: cellHeight)
                }
            }
        }
        .aspectRatio(120.0 / 64.0, contentMode: .fit)
    }

    private func photoCell(pose: Pose, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = poseImages[pose] {
                NavigationLink(destination: FullPhotoView(image: image, title: "\(pose.title) photo")) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
                        .accessibilityLabel("\(pose.title) progress photo")
                }
            } else {
                RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                    .fill(ProofTheme.paperLo.opacity(0.6))
                    .frame(width: width, height: height)
                    .overlay(
                        Text("—")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(ProofTheme.inkSoft.opacity(0.5))
                    )
            }

            Text(pose.title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(ProofTheme.paperHi)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    private var qualityNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ProofTheme.statusFair)

                Text("Some shots may be hard to compare")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ProofTheme.inkPrimary)
            }

            ForEach(Array(qualityIssues.enumerated()), id: \.offset) { _, item in
                Text("\(item.pose.title): \(item.issue)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ProofTheme.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notesBackground)
    }

    @ViewBuilder
    private var notesBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: ProofTheme.radiusMD))
        } else {
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .fill(ProofTheme.paperHi.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                        .stroke(ProofTheme.statusFair.opacity(0.3), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isFromHistory {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProofTheme.statusPoor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(deleteBackground)
            }
            .accessibilityLabel("Delete this session")
        } else {
            VStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProofTheme.paperHi)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(ProofTheme.inkPrimary))
                }
                .accessibilityLabel("Close review")

                if savedSuccessfully {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ProofTheme.statusGood)
                        Text("Saved to Photos")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProofTheme.statusGood)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(savedBackground)
                } else {
                    Button {
                        Task { await saveToCamera() }
                    } label: {
                        Text(isSaving ? "Saving…" : "Save to Photos")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProofTheme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .disabled(isSaving)
                    .accessibilityLabel("Save photos to Photos")
                }
            }
        }
    }

    @ViewBuilder
    private var deleteBackground: some View {
        if #available(iOS 26, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(ProofTheme.paperHi.opacity(0.6))
                .overlay(Capsule().stroke(ProofTheme.statusPoor.opacity(0.2), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var savedBackground: some View {
        Capsule()
            .fill(ProofTheme.statusGood.opacity(0.12))
            .overlay(Capsule().stroke(ProofTheme.statusGood.opacity(0.3), lineWidth: 1))
    }

    private func saveToCamera() async {
        await MainActor.run { isSaving = true }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            await MainActor.run { isSaving = false }
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
            }
            ProofTheme.hapticSuccess()
        } catch {
            await MainActor.run { isSaving = false }
        }
    }

    private func deleteSession() {
        guard let session else { return }
        modelContext.delete(session)
        dismiss()
    }
}
