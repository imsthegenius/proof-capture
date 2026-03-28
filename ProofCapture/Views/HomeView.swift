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
                        .foregroundStyle(ProofTheme.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)

            Spacer()

            // Last session info OR first-time guidance
            if let last = lastSession {
                Text("Last session")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                Text(last.date, style: .relative)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .padding(.top, ProofTheme.spacingXS)
            } else {
                VStack(spacing: ProofTheme.spacingSM) {
                    Image(systemName: "iphone.rear.camera")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text("Prop your phone up")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                    Text("5\u{2013}6 feet away, waist height")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
            }

            Spacer()
                .frame(height: ProofTheme.spacingXL)

            // Capture button
            NavigationLink(destination: SessionView()) {
                VStack(spacing: ProofTheme.spacingSM) {
                    ZStack {
                        Circle()
                            .stroke(ProofTheme.accent, lineWidth: 2)
                            .frame(width: 88, height: 88)

                        Image(systemName: "camera")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(ProofTheme.accent)
                            .accessibilityHidden(true)
                    }

                    Text("Start Session")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                }
            }
            .accessibilityLabel("Start photo session")
            .simultaneousGesture(TapGesture().onEnded { ProofTheme.hapticLight() })

            Spacer()

            // History link
            NavigationLink(destination: HistoryView()) {
                HStack {
                    Text("History")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .frame(height: 52)
                .padding(.horizontal, ProofTheme.spacingMD)
            }
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
