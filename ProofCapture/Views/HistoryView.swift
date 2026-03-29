import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PhotoSession.date, order: .reverse) private var sessions: [PhotoSession]
    @Environment(\.modelContext) private var modelContext
    @State private var sessionToDelete: PhotoSession?
    @State private var showDeleteConfirmation = false
    @State private var isCompareMode = false
    @State private var compareSelections: [PhotoSession] = []
    @State private var visibleRows: Set<UUID> = []

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
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                }
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("This session and its photos will be permanently deleted.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()

            VStack(spacing: ProofTheme.spacingXS) {
                Text("0")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(ProofTheme.accent)

                Text("sessions")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
            }

            Spacer()

            NavigationLink(destination: SessionView()) {
                Text("Start your first session")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .accessibilityLabel("Start your first photo session")
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            // Compare toggle
            if sessions.count >= 2 {
                Section {
                    if isCompareMode {
                        VStack(spacing: ProofTheme.spacingSM) {
                            Text("Select 2 sessions to compare")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(ProofTheme.textTertiary)

                            if compareSelections.count == 2 {
                                NavigationLink(destination: ComparisonView(
                                    sessionA: compareSelections[0],
                                    sessionB: compareSelections[1]
                                )) {
                                    Text("Compare")
                                }
                                .buttonStyle(ProofTheme.ProofButtonStyle())
                            }

                            Button {
                                isCompareMode = false
                                compareSelections = []
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundStyle(ProofTheme.textTertiary)
                            }
                        }
                        .frame(height: 88)
                    } else {
                        Button {
                            isCompareMode = true
                            compareSelections = []
                        } label: {
                            HStack(spacing: ProofTheme.spacingMD) {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundStyle(ProofTheme.accent)

                                Text("Compare sessions")
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundStyle(ProofTheme.textSecondary)
                            }
                            .frame(height: 44)
                        }
                        .accessibilityLabel("Compare two sessions")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: ProofTheme.spacingMD, bottom: 0, trailing: ProofTheme.spacingMD))
            }

            // Session rows
            Section {
                ForEach(sessions) { session in
                    if isCompareMode {
                        Button {
                            toggleCompareSelection(session)
                        } label: {
                            HStack {
                                sessionRow(session)

                                if compareSelections.contains(where: { $0.id == session.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundStyle(ProofTheme.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.system(size: 20, weight: .ultraLight))
                                        .foregroundStyle(ProofTheme.textTertiary)
                                }
                            }
                        }
                        .accessibilityLabel("Select session from \(session.date.formatted(.dateTime.month(.abbreviated).day().year())) for comparison")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: ProofTheme.spacingMD, bottom: 0, trailing: ProofTheme.spacingMD))
                        .listRowSeparator(.hidden)
                        .opacity(visibleRows.contains(session.id) ? 1 : 0)
                        .offset(y: visibleRows.contains(session.id) ? 0 : 12)
                        .animation(.easeOut(duration: 0.25), value: visibleRows.contains(session.id))
                        .onAppear {
                            let index = sessions.firstIndex(where: { $0.id == session.id }) ?? 0
                            let delay = min(Double(index) * 0.05, 0.25)
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                visibleRows.insert(session.id)
                            }
                        }
                    } else {
                        NavigationLink(destination: ReviewView(session: session)) {
                            sessionRow(session)
                        }
                        .accessibilityLabel("Session from \(session.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: ProofTheme.spacingMD, bottom: 0, trailing: ProofTheme.spacingMD))
                        .listRowSeparator(.hidden)
                        .opacity(visibleRows.contains(session.id) ? 1 : 0)
                        .offset(y: visibleRows.contains(session.id) ? 0 : 12)
                        .animation(.easeOut(duration: 0.25), value: visibleRows.contains(session.id))
                        .onAppear {
                            let index = sessions.firstIndex(where: { $0.id == session.id }) ?? 0
                            let delay = min(Double(index) * 0.05, 0.25)
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                visibleRows.insert(session.id)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    guard !isCompareMode else { return }
                    if let index = indexSet.first {
                        sessionToDelete = sessions[index]
                        showDeleteConfirmation = true
                    }
                }
                .deleteDisabled(isCompareMode)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Session Row

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
                            .frame(height: 120)
                            .clipped()
                            .accessibilityLabel("\(pose.title) photo")
                    } else {
                        Rectangle()
                            .fill(ProofTheme.surface)
                            .frame(height: 120)
                            .accessibilityLabel("\(pose.title) photo missing")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
        .padding(.vertical, ProofTheme.spacingMD)
    }

    // MARK: - Actions

    private func deleteSession(_ session: PhotoSession) {
        modelContext.delete(session)
        sessionToDelete = nil
    }

    private func toggleCompareSelection(_ session: PhotoSession) {
        if let index = compareSelections.firstIndex(where: { $0.id == session.id }) {
            compareSelections.remove(at: index)
        } else if compareSelections.count < 2 {
            compareSelections.append(session)
        } else {
            // Replace the first selection
            compareSelections[0] = compareSelections[1]
            compareSelections[1] = session
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .preferredColorScheme(.dark)
}
