import SwiftUI

struct ComparisonView: View {
    let sessionA: PhotoSession
    let sessionB: PhotoSession
    @State private var selectedPose: Pose = .front

    private var earlierSession: PhotoSession {
        sessionA.date < sessionB.date ? sessionA : sessionB
    }

    private var recentSession: PhotoSession {
        sessionA.date < sessionB.date ? sessionB : sessionA
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pose picker buttons
            posePicker

            // Swipeable photo comparison
            TabView(selection: $selectedPose) {
                ForEach(Pose.allCases) { pose in
                    comparisonColumns(pose: pose)
                        .tag(pose)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: selectedPose)

            // Date labels
            dateLabels
        }
        .background(ProofTheme.background)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pose Picker

    private var posePicker: some View {
        HStack(spacing: 0) {
            ForEach(Pose.allCases) { pose in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedPose = pose
                    }
                    ProofTheme.hapticLight()
                } label: {
                    VStack(spacing: ProofTheme.spacingXS) {
                        Text(pose.title)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(selectedPose == pose ? ProofTheme.textPrimary : ProofTheme.textTertiary)

                        Rectangle()
                            .fill(selectedPose == pose ? ProofTheme.accent : Color.clear)
                            .frame(height: 1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .accessibilityLabel("\(pose.title) pose comparison")
                .accessibilityAddTraits(selectedPose == pose ? .isSelected : [])
            }
        }
        .padding(.horizontal, ProofTheme.spacingMD)
    }

    // MARK: - Comparison Columns

    private func comparisonColumns(pose: Pose) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                photoColumn(session: earlierSession, pose: pose, availableHeight: geometry.size.height)
                photoColumn(session: recentSession, pose: pose, availableHeight: geometry.size.height)
            }
        }
    }

    private func photoColumn(session: PhotoSession, pose: Pose, availableHeight: CGFloat) -> some View {
        Group {
            if let image = session.photo(for: pose) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: availableHeight)
                    .clipped()
                    .accessibilityLabel("\(pose.title) photo from \(session.date.formatted(.dateTime.month(.abbreviated).day()))")
            } else {
                Rectangle()
                    .fill(ProofTheme.surface)
                    .frame(maxWidth: .infinity, maxHeight: availableHeight)
                    .overlay(
                        Text("No photo")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
                    .accessibilityLabel("No \(pose.title) photo available")
            }
        }
    }

    // MARK: - Date Labels

    private var dateLabels: some View {
        HStack {
            VStack(spacing: 2) {
                Text("Earlier")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                Text(earlierSession.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Earlier session, \(earlierSession.date.formatted(.dateTime.month(.abbreviated).day()))")

            VStack(spacing: 2) {
                Text("Recent")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                Text(recentSession.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recent session, \(recentSession.date.formatted(.dateTime.month(.abbreviated).day()))")
        }
        .padding(.vertical, ProofTheme.spacingSM)
    }
}
