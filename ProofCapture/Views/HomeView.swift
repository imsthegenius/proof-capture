import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \PhotoSession.date, order: .reverse) private var sessions: [PhotoSession]

    private var lastSession: PhotoSession? { sessions.first }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("PROOF")
                    .font(.system(size: 17, weight: .light))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.textTertiary)

                Spacer()

                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)

            Spacer()

            // Last session info
            if let last = lastSession {
                Text("Last session")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                Text(last.date, style: .relative)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .padding(.top, ProofTheme.spacingXS)
            }

            Spacer()
                .frame(height: ProofTheme.spacingXL)

            // Capture button
            NavigationLink(destination: SessionView()) {
                VStack(spacing: ProofTheme.spacingSM) {
                    ZStack {
                        Circle()
                            .fill(ProofTheme.accent)
                            .frame(width: 80, height: 80)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(ProofTheme.background)
                            .accessibilityHidden(true)
                    }

                    Text("Start Session")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                }
            }
            .accessibilityLabel("Start photo session")

            Spacer()

            // Bottom links
            NavigationLink(destination: HistoryView()) {
                Text("History")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .frame(minHeight: 44)
            }
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
