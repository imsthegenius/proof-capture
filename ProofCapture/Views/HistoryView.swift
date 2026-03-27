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
        List {
            if sessions.count >= 2 {
                Section {
                    NavigationLink(destination: ComparisonView(sessionA: sessions[0], sessionB: sessions[1])) {
                        HStack(spacing: ProofTheme.spacingMD) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(ProofTheme.accent)

                            Text("Compare last two sessions")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(ProofTheme.textPrimary)
                        }
                        .padding(.vertical, ProofTheme.spacingXS)
                    }
                    .listRowBackground(ProofTheme.surface)
                    .listRowSeparatorTint(ProofTheme.separator)
                }
            }

            Section {
                ForEach(sessions) { session in
                    NavigationLink(destination: ReviewView(session: session)) {
                        sessionRow(session)
                    }
                    .listRowBackground(ProofTheme.background)
                    .listRowSeparatorTint(ProofTheme.separator)
                }
                .onDelete(perform: deleteSessions)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func sessionRow(_ session: PhotoSession) -> some View {
        HStack(spacing: ProofTheme.spacingMD) {
            thumbnails(for: session)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXS) {
                Text(session.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)

                Text(session.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }

            Spacer()

            Text("\(session.completedPoseCount) of 3")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        }
        .padding(.vertical, ProofTheme.spacingXS)
    }

    private func thumbnails(for session: PhotoSession) -> some View {
        HStack(spacing: -ProofTheme.spacingSM) {
            ForEach(Pose.allCases) { pose in
                if let image = session.photo(for: pose) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                        .accessibilityLabel("\(pose.title) photo")
                } else {
                    RoundedRectangle(cornerRadius: ProofTheme.radiusSM)
                        .fill(ProofTheme.surface)
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .preferredColorScheme(.dark)
}
