import SwiftUI

/// Side-by-side comparison — dark world. Glass capsule pose picker, full-bleed
/// photos with paperHi date overlays, status pill showing the time gap.
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
        ZStack {
            ProofTheme.background.ignoresSafeArea()

            VStack(spacing: ProofTheme.spacingMD) {
                posePicker
                    .padding(.horizontal, ProofTheme.spacingMD)

                comparisonSurface

                gapPill
                    .padding(.bottom, ProofTheme.spacingMD)
            }
            .padding(.top, ProofTheme.spacingMD)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .proofDynamicType()
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
        }
    }

    private var posePicker: some View {
        HStack(spacing: 0) {
            ForEach(Pose.allCases) { pose in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedPose = pose
                    }
                    ProofTheme.hapticLight()
                } label: {
                    Text(pose.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selectedPose == pose ? ProofTheme.background : ProofTheme.paperHi)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(selectedPose == pose ? ProofTheme.paperHi : Color.clear)
                                .padding(3)
                        )
                }
                .accessibilityLabel("\(pose.title) pose")
                .accessibilityAddTraits(selectedPose == pose ? .isSelected : [])
            }
        }
        .background(pickerBackground)
    }

    @ViewBuilder
    private var pickerBackground: some View {
        if #available(iOS 26, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(ProofTheme.surface)
                .overlay(Capsule().stroke(ProofTheme.paperHi.opacity(0.08), lineWidth: 1))
        }
    }

    private var comparisonSurface: some View {
        TabView(selection: $selectedPose) {
            ForEach(Pose.allCases) { pose in
                photoPair(pose: pose).tag(pose)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    private func photoPair(pose: Pose) -> some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                photoColumn(session: earlierSession, pose: pose, label: "EARLIER", height: geo.size.height)
                photoColumn(session: recentSession, pose: pose, label: "RECENT", height: geo.size.height)
            }
        }
    }

    private func photoColumn(session: PhotoSession, pose: Pose, label: String, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = session.photo(for: pose) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: height)
                    .clipped()
                    .accessibilityLabel("\(pose.title) photo from \(session.date.formatted(.dateTime.month(.abbreviated).day()))")
            } else {
                Rectangle()
                    .fill(ProofTheme.surface)
                    .frame(maxWidth: .infinity, maxHeight: height)
                    .overlay(
                        Text("—")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
                    .accessibilityLabel("No \(pose.title) photo")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(ProofTheme.paperHi.opacity(0.7))

                Text(session.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ProofTheme.paperHi)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(12)
        }
    }

    private var gapPill: some View {
        Text(weekDifferenceText)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(ProofTheme.statusGood)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(ProofTheme.statusGood.opacity(0.12))
                    .overlay(Capsule().stroke(ProofTheme.statusGood.opacity(0.25), lineWidth: 1))
            )
            .accessibilityLabel("Sessions are \(weekDifferenceText)")
    }

    private var weekDifferenceText: String {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: earlierSession.date)
        let end = calendar.startOfDay(for: recentSession.date)
        let dayDifference = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)

        guard dayDifference > 0 else { return "SAME DAY" }
        let weeks = max(0, calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? (dayDifference / 7))
        guard weeks > 0 else { return "WITHIN 1 WEEK" }
        return weeks == 1 ? "1 WEEK LATER" : "\(weeks) WEEKS LATER"
    }
}
