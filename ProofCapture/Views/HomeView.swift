import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(
        filter: #Predicate<PhotoSession> { $0.isComplete },
        sort: \PhotoSession.date,
        order: .reverse
    ) private var sessions: [PhotoSession]
    @Query(
        filter: #Predicate<PhotoSession> { $0.isComplete == false },
        sort: \PhotoSession.date,
        order: .reverse
    ) private var draftSessions: [PhotoSession]

    private var lastSession: PhotoSession? { sessions.first }
    private var activeDraft: PhotoSession? { draftSessions.first }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var earliestCompletedSessionDate: Date? { sessions.last?.date }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ProofTheme.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)

            Spacer()
            Spacer()

            if let draft = activeDraft {
                VStack(spacing: ProofTheme.spacingMD) {
                    Text("Draft saved")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textSecondary)

                    Text("Resume at \(draft.currentPose.title.lowercased())")
                        .proofFont(24, weight: .ultraLight, relativeTo: .title2)
                        .foregroundStyle(ProofTheme.accent)

                    Text("\(draft.completedPoseCount) of 3 poses captured")
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Draft saved. Resume at the \(draft.currentPose.title.lowercased()) pose. \(draft.completedPoseCount) of 3 poses captured.")
            } else if let last = lastSession {
                lastSessionCard(for: last)
            } else {
                VStack(spacing: ProofTheme.spacingSM) {
                    Image(systemName: "iphone.rear.camera")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .accessibilityHidden(true)
                    Text("Prop your phone up")
                        .proofFont(17, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textSecondary)
                    Text("5\u{2013}6 feet away, waist height")
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text("Overhead light for best results")
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Setup tip: Prop your phone up, 5 to 6 feet away at waist height, with overhead light for best results")
            }

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            NavigationLink(destination: SessionView()) {
                VStack(spacing: ProofTheme.spacingSM) {
                    ZStack {
                        if #available(iOS 26, *) {
                            Circle()
                                .fill(.clear)
                                .frame(width: 100, height: 100)
                                .overlay {
                                    Image(systemName: "camera")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundStyle(ProofTheme.accent)
                                }
                                .glassEffect(.regular.interactive(), in: .circle)
                        } else {
                            Circle()
                                .stroke(ProofTheme.accent, lineWidth: 2)
                                .frame(width: 100, height: 100)

                            Image(systemName: "camera")
                                .font(.system(size: 32, weight: .ultraLight))
                                .foregroundStyle(ProofTheme.accent)
                        }
                    }

                    Text(activeDraft == nil ? "Start Session" : "Resume Session")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textPrimary)
                }
            }
            .accessibilityLabel(activeDraft == nil ? "Start photo session" : "Resume photo session")
            .simultaneousGesture(TapGesture().onEnded { ProofTheme.hapticMedium() })

            Spacer()

            NavigationLink(destination: HistoryView()) {
                HStack {
                    Text("History")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .frame(minHeight: 52)
                .padding(.horizontal, ProofTheme.spacingMD)
            }
            .accessibilityLabel("View session history")
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proofDynamicType()
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func lastSessionCard(for session: PhotoSession) -> some View {
        VStack(spacing: ProofTheme.spacingMD) {
            VStack(spacing: ProofTheme.spacingSM) {
                Text(heroMessage(for: session))
                    .proofFont(12, weight: .light, relativeTo: .caption1)
                    .tracking(2)
                    .foregroundStyle(ProofTheme.textTertiary)

                Text(heroSubtitle(for: session))
                    .proofFont(27, weight: .light, relativeTo: .title2)
                    .foregroundStyle(ProofTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sessionPreview(for: session)

            HStack(spacing: ProofTheme.spacingMD) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sessions.count)")
                        .proofFont(34, weight: .ultraLight, relativeTo: .largeTitle)
                        .foregroundStyle(ProofTheme.accent)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: sessions.count)
                    Text(sessions.count == 1 ? "session saved" : "sessions saved")
                        .proofFont(12, weight: .light, relativeTo: .caption1)
                        .foregroundStyle(ProofTheme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Updated")
                        .proofFont(12, weight: .light, relativeTo: .caption1)
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text(session.date, style: .relative)
                        .proofFont(14, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textSecondary)
                }
            }
        }
        .padding(ProofTheme.spacingLG)
        .frame(maxWidth: .infinity)
        .background(ProofTheme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                .stroke(ProofTheme.separator, lineWidth: 1)
        )
        .padding(.horizontal, ProofTheme.spacingMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heroMessage(for: session)). \(heroSubtitle(for: session)). \(sessions.count) sessions saved.")
    }

    private func heroMessage(for session: PhotoSession) -> String {
        switch daysSinceLastSession(for: session.date) {
        case 0:
            return "Check-in complete"
        case 1...7:
            return "Week \(weekIndex(for: session.date))"
        case 8...14:
            return "Time for a check-in"
        default:
            return "Welcome back"
        }
    }

    private func heroSubtitle(for session: PhotoSession) -> String {
        switch daysSinceLastSession(for: session.date) {
        case 0:
            return "Captured today"
        case 1:
            return "Last session yesterday"
        case 2...7:
            return "Last session \(daysSinceLastSession(for: session.date)) days ago"
        case 8...14:
            return "Your last check-in was \(daysSinceLastSession(for: session.date)) days ago"
        default:
            return "Start a fresh check-in"
        }
    }

    @ViewBuilder
    private func sessionPreview(for session: PhotoSession) -> some View {
        let stripHeight: CGFloat = 100

        if hasFullPhotoStrip(session) {
            HStack(spacing: 2) {
                ForEach(Pose.allCases) { pose in
                    if let image = session.photo(for: pose) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: stripHeight)
                            .clipped()
                            .accessibilityLabel("\(pose.title) photo")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        } else if let frontPhoto = session.photo(for: .front) {
            Image(uiImage: frontPhoto)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 78, height: stripHeight)
                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                .accessibilityLabel("Last session front photo")
        }
    }

    private func hasFullPhotoStrip(_ session: PhotoSession) -> Bool {
        Pose.allCases.allSatisfy { session.photo(for: $0) != nil }
    }

    private func daysSinceLastSession(for date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        return max(0, days)
    }

    private func weekIndex(for date: Date) -> Int {
        guard let earliest = earliestCompletedSessionDate else { return 1 }

        let start = calendar.startOfDay(for: earliest)
        let current = calendar.startOfDay(for: date)
        let dayOffset = max(0, calendar.dateComponents([.day], from: start, to: current).day ?? 0)
        return (dayOffset / 7) + 1
    }
}
