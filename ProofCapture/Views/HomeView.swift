import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \PhotoSession.date, order: .reverse) private var sessions: [PhotoSession]

    private var lastSession: PhotoSession? { sessions.first }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — settings gear only
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

            // Last session info OR first-time guidance
            if let last = lastSession {
                VStack(spacing: ProofTheme.spacingMD) {
                    // Session count — large thin number, Swiss style
                    Text("\(sessions.count)")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(ProofTheme.accent)
                    Text(sessions.count == 1 ? "session" : "sessions")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)

                    // Last session thumbnail + date
                    if let frontPhoto = last.photo(for: .front) {
                        Image(uiImage: frontPhoto)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                            .accessibilityLabel("Last session front photo")
                    }

                    Text(last.date, style: .relative)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                        + Text(" ago")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(sessions.count) sessions completed. Last session was \(last.date, style: .relative) ago")
            } else {
                VStack(spacing: ProofTheme.spacingSM) {
                    Image(systemName: "iphone.rear.camera")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .accessibilityHidden(true)
                    Text("Prop your phone up")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                    Text("5\u{2013}6 feet away, waist height")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                    Text("Overhead light for best results")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Setup tip: Prop your phone up, 5 to 6 feet away at waist height, with overhead light for best results")
            }

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            // Hero capture button
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

                    Text("Start Session")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textPrimary)
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
            .accessibilityLabel("View session history")
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
