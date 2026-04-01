import SwiftUI

struct ComparisonView: View {
    let sessionA: PhotoSession
    let sessionB: PhotoSession
    @State private var selectedPose: Pose = .front
    @State private var hasAppeared = false

    private var earlierSession: PhotoSession {
        sessionA.date < sessionB.date ? sessionA : sessionB
    }

    private var recentSession: PhotoSession {
        sessionA.date < sessionB.date ? sessionB : sessionA
    }

    var body: some View {
        VStack(spacing: 0) {
            posePicker

            comparisonSurface

            dateLabels
        }
        .proofDynamicType()
        .background(ProofTheme.background)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                hasAppeared = true
            }
        }
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
                            .proofFont(13, weight: .light, relativeTo: .footnote)
                            .foregroundStyle(selectedPose == pose ? ProofTheme.textPrimary : ProofTheme.textTertiary)

                        Rectangle()
                            .fill(selectedPose == pose ? ProofTheme.accent : Color.clear)
                            .frame(height: 1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("\(pose.title) pose comparison")
                .accessibilityAddTraits(selectedPose == pose ? .isSelected : [])
            }
        }
        .padding(.horizontal, ProofTheme.spacingMD)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.45).delay(0.05), value: hasAppeared)
    }

    private var comparisonSurface: some View {
        TabView(selection: $selectedPose) {
            ForEach(Pose.allCases) { pose in
                comparisonColumns(pose: pose)
                    .tag(pose)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.985)
        .offset(y: hasAppeared ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.12), value: hasAppeared)
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
                            .proofFont(13, weight: .light, relativeTo: .footnote)
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
                    .accessibilityLabel("No \(pose.title) photo available")
            }
        }
    }

    // MARK: - Date Labels

    private var dateLabels: some View {
        VStack(spacing: ProofTheme.spacingSM) {
            Text(weekDifferenceText)
                .proofFont(12, weight: .light, relativeTo: .caption1)
                .foregroundStyle(ProofTheme.statusGood)
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.vertical, ProofTheme.spacingXS + 2)
                .background(ProofTheme.statusGood.opacity(0.12), in: Capsule())
                .accessibilityLabel("Sessions are \(weekDifferenceText)")

            HStack {
                VStack(spacing: 2) {
                    Text("Earlier")
                        .proofFont(11, weight: .light, relativeTo: .caption2)
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text(earlierSession.date.formatted(.dateTime.month(.abbreviated).day()))
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Earlier session, \(earlierSession.date.formatted(.dateTime.month(.abbreviated).day()))")

                VStack(spacing: 2) {
                    Text("Recent")
                        .proofFont(11, weight: .light, relativeTo: .caption2)
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text(recentSession.date.formatted(.dateTime.month(.abbreviated).day()))
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recent session, \(recentSession.date.formatted(.dateTime.month(.abbreviated).day()))")
            }
        }
        .padding(.vertical, ProofTheme.spacingSM)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.45).delay(0.18), value: hasAppeared)
    }

    private var weekDifferenceText: String {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: earlierSession.date)
        let end = calendar.startOfDay(for: recentSession.date)
        let dayDifference = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)

        guard dayDifference > 0 else { return "Same day" }

        let weekDifference = max(0, calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? (dayDifference / 7))
        guard weekDifference > 0 else { return "Less than 1 week later" }

        let weekLabel = weekDifference == 1 ? "week" : "weeks"
        return "\(weekDifference) \(weekLabel) later"
    }
}
