import SwiftData
import SwiftUI

/// Camera tab landing — dark world. Photo-booth simplicity:
/// settings gear top-right, large session counter, BIG white shutter button center,
/// last-session timestamp below. Tap shutter → SessionView.
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

    @State private var goToSession = false
    @State private var visible = false

    private var lastSession: PhotoSession? { sessions.first }
    private var activeDraft: PhotoSession? { draftSessions.first }

    var body: some View {
        ZStack {
            ProofTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.top, ProofTheme.spacingSM)

                Spacer()

                heroBlock

                Spacer()

                shutterButton

                Spacer()

                Color.clear.frame(height: 100)
            }
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goToSession) {
            SessionView()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroBlock: some View {
        if let draft = activeDraft {
            VStack(spacing: 8) {
                Text("DRAFT IN PROGRESS")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.statusFair)

                Text("Resume at \(draft.currentPose.title.lowercased())")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi)

                Text("\(draft.completedPoseCount) of 3 captured")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if let last = lastSession {
            VStack(spacing: 6) {
                Text("\(sessions.count)")
                    .font(.system(size: 96, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: sessions.count)

                Text(sessions.count == 1 ? "session captured" : "sessions captured")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(ProofTheme.textSecondary)

                Text("Last \(relativeDate(last.date))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sessions.count) sessions captured. Last session \(relativeDate(last.date)).")
        } else {
            VStack(spacing: 14) {
                Text("READY WHEN YOU ARE")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.textTertiary)

                Text("Prop your phone\nstep two metres back")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Shutter

    private var shutterButton: some View {
        Button {
            ProofTheme.hapticMedium()
            goToSession = true
        } label: {
            ZStack {
                Circle()
                    .stroke(ProofTheme.paperHi, lineWidth: 4)
                    .frame(width: 96, height: 96)

                Circle()
                    .fill(ProofTheme.paperHi)
                    .frame(width: 78, height: 78)
            }
        }
        .accessibilityLabel(activeDraft == nil ? "Start session" : "Resume session")
    }

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "1 week ago"
        case 14...29: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }
}
