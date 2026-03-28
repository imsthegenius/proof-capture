import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PhotoSession.date, order: .reverse) private var sessions: [PhotoSession]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .background(ProofTheme.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack {
            Spacer()

            Text("No sessions yet")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Compare link
                if sessions.count >= 2 {
                    NavigationLink(destination: ComparisonView(sessionA: sessions[0], sessionB: sessions[1])) {
                        HStack(spacing: ProofTheme.spacingMD) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(ProofTheme.accent)

                            Text("Compare last two sessions")
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
                    .simultaneousGesture(TapGesture().onEnded { ProofTheme.hapticLight() })

                    Rectangle()
                        .fill(ProofTheme.separator)
                        .frame(height: 1)
                        .padding(.horizontal, ProofTheme.spacingMD)
                        .padding(.bottom, ProofTheme.spacingSM)
                }

                // Session rows
                ForEach(sessions) { session in
                    NavigationLink(destination: ReviewView(session: session)) {
                        sessionRow(session)
                    }
                    .simultaneousGesture(TapGesture().onEnded { ProofTheme.hapticLight() })
                    .padding(.horizontal, ProofTheme.spacingMD)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func sessionRow(_ session: PhotoSession) -> some View {
        VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
            // Date header
            HStack {
                Text(session.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)
                Spacer()
                Text(session.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }

            // Photo strip — 3 photos side by side
            HStack(spacing: 2) {
                ForEach(Pose.allCases) { pose in
                    if let image = session.photo(for: pose) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipped()
                            .accessibilityLabel("\(pose.title) photo")
                    } else {
                        Rectangle()
                            .fill(ProofTheme.surface)
                            .frame(height: 100)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
        .padding(.vertical, ProofTheme.spacingSM)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .preferredColorScheme(.dark)
}
