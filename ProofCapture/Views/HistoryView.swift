import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(
        filter: #Predicate<PhotoSession> { $0.isComplete },
        sort: \PhotoSession.date,
        order: .reverse
    ) private var sessions: [PhotoSession]
    @Environment(\.modelContext) private var modelContext
    @State private var sessionToDelete: PhotoSession?
    @State private var showDeleteConfirmation = false
    @State private var isCompareMode = false
    @State private var compareSelections: [PhotoSession] = []
    @State private var visibleRows: Set<UUID> = []

    private var calendar: Calendar { .autoupdatingCurrent }
    private var earliestSessionDate: Date? { sessions.last?.date }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .proofDynamicType()
        .background(ProofTheme.paperHi)
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
                    .proofFont(48, weight: .medium, relativeTo: .largeTitle)
                    .foregroundStyle(ProofTheme.inkPrimary)

                Text("sessions")
                    .proofFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(ProofTheme.inkSoft)
            }

            Spacer()

            NavigationLink(destination: SessionView()) {
                Text("Start your first session")
                    .proofFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(ProofTheme.inkPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .liquidGlassCapsule(.paperLight)
            .accessibilityLabel("Start your first photo session")
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            if sessions.count >= 2 {
                Section {
                    if isCompareMode {
                        VStack(spacing: ProofTheme.spacingSM) {
                            Text("Select 2 sessions to compare")
                                .proofFont(13, weight: .regular, relativeTo: .footnote)
                                .foregroundStyle(ProofTheme.inkSoft)

                            if compareSelections.count == 2 {
                                NavigationLink(destination: ComparisonView(
                                    sessionA: compareSelections[0],
                                    sessionB: compareSelections[1]
                                )) {
                                    Text("Compare")
                                        .proofFont(15, weight: .medium, relativeTo: .body)
                                        .foregroundStyle(ProofTheme.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 52)
                                }
                                .buttonStyle(.plain)
                                .liquidGlassCapsule(.paperLight)
                            }

                            Button {
                                isCompareMode = false
                                compareSelections = []
                            } label: {
                                Text("Cancel")
                                    .proofFont(13, weight: .medium, relativeTo: .footnote)
                                    .foregroundStyle(ProofTheme.inkSoft)
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
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(ProofTheme.inkPrimary)

                                Text("Compare sessions")
                                    .proofFont(15, weight: .medium, relativeTo: .body)
                                    .foregroundStyle(ProofTheme.inkPrimary)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Compare two sessions")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: ProofTheme.spacingMD, bottom: 0, trailing: ProofTheme.spacingMD))
            }

            Section {
                ForEach(sessions) { session in
                    if isCompareMode {
                        Button {
                            toggleCompareSelection(session)
                        } label: {
                            HStack(alignment: .top, spacing: ProofTheme.spacingSM) {
                                sessionRow(session)

                                if compareSelections.contains(where: { $0.id == session.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(ProofTheme.inkPrimary)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundStyle(ProofTheme.inkSoft)
                                }
                            }
                        }
                        .accessibilityLabel(historyAccessibilityLabel(for: session, action: "Select"))
                        .modifier(RowRevealModifier(isVisible: visibleRows.contains(session.id)))
                        .onAppear { scheduleRowReveal(for: session) }
                    } else {
                        NavigationLink(destination: ReviewView(session: session)) {
                            sessionRow(session)
                        }
                        .accessibilityLabel(historyAccessibilityLabel(for: session))
                        .modifier(RowRevealModifier(isVisible: visibleRows.contains(session.id)))
                        .onAppear { scheduleRowReveal(for: session) }
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
        VStack(alignment: .leading, spacing: ProofTheme.spacingMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week \(weekIndex(for: session))")
                    .proofFont(12, weight: .medium, relativeTo: .caption1)
                    .tracking(1.8)
                    .foregroundStyle(ProofTheme.inkSoft)

                Text(session.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .proofFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(ProofTheme.inkPrimary)
            }

            HStack(spacing: 2) {
                ForEach(Pose.allCases) { pose in
                    sessionPhotoTile(session, pose: pose)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
        .padding(ProofTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProofTheme.paperLo.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                .stroke(ProofTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sessionPhotoTile(_ session: PhotoSession, pose: Pose) -> some View {
        if let image = session.photo(for: pose) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
                .accessibilityLabel("\(pose.title) photo")
        } else {
            Rectangle()
                .fill(ProofTheme.paperLo)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .accessibilityLabel("\(pose.title) photo missing")
        }
    }

    private func weekIndex(for session: PhotoSession) -> Int {
        guard let earliest = earliestSessionDate else { return 1 }

        let start = calendar.startOfDay(for: earliest)
        let current = calendar.startOfDay(for: session.date)
        let dayOffset = max(0, calendar.dateComponents([.day], from: start, to: current).day ?? 0)
        return (dayOffset / 7) + 1
    }

    private func historyAccessibilityLabel(for session: PhotoSession, action: String = "Session") -> String {
        let date = session.date.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(action) week \(weekIndex(for: session)), \(date)"
    }

    private func scheduleRowReveal(for session: PhotoSession) {
        let index = sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        let delay = min(Double(index) * ProofTheme.staggerShort, ProofTheme.staggerLong)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled else { return }
            visibleRows.insert(session.id)
        }
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
            compareSelections[0] = compareSelections[1]
            compareSelections[1] = session
        }
    }
}

private struct RowRevealModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: ProofTheme.spacingMD, bottom: 0, trailing: ProofTheme.spacingMD))
            .listRowSeparator(.hidden)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(.easeOut(duration: ProofTheme.animationFast), value: isVisible)
    }
}

#Preview {
    NavigationStack {
    HistoryView()
    }
}
