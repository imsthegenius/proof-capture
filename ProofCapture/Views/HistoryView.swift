import SwiftData
import SwiftUI

/// Albums tab — light/cream "paper" surface, 3-column grid of session thumbnails,
/// each cell paginates through Front → Side → Back. Replaces the prior dark list-based History.
struct AlbumsView: View {
    @Query(
        filter: #Predicate<PhotoSession> { $0.isComplete },
        sort: \PhotoSession.date,
        order: .reverse
    ) private var sessions: [PhotoSession]

    @State private var selectedMonth: Date = .now
    @State private var sessionForReview: PhotoSession?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 3
    )

    private var calendar: Calendar { .autoupdatingCurrent }

    private var filteredSessions: [PhotoSession] {
        sessions.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }

    private var monthLabel: String {
        selectedMonth.formatted(.dateTime.month(.wide))
    }

    var body: some View {
        ZStack {
            paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .padding(.bottom, 80)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sessionForReview) { session in
            NavigationStack {
                ReviewView(session: session)
            }
        }
    }

    private var paperBackground: some View {
        LinearGradient(
            colors: [ProofTheme.paperHi, ProofTheme.paperLo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ProofTheme.spacingMD) {
            HStack(alignment: .center) {
                Text("Albums")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(ProofTheme.inkPrimary)

                Spacer()

                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(ProofTheme.inkPrimary)
                }
                .accessibilityLabel("Profile and settings")
            }

            monthPill
        }
        .padding(.horizontal, ProofTheme.spacingMD)
        .padding(.top, ProofTheme.spacingMD)
    }

    private var monthPill: some View {
        Menu {
            ForEach(monthOptions, id: \.self) { month in
                Button {
                    withAnimation(.easeInOut(duration: ProofTheme.animationFast)) {
                        selectedMonth = month
                    }
                } label: {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ProofTheme.inkPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ProofTheme.inkSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(monthPillBackground)
        }
        .accessibilityLabel("Filter by month, currently \(monthLabel)")
    }

    @ViewBuilder
    private var monthPillBackground: some View {
        if #available(iOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    private var monthOptions: [Date] {
        guard !sessions.isEmpty else { return [.now] }
        let dates = sessions.map { calendar.startOfMonth(for: $0.date) }
        return Array(Set(dates)).sorted(by: >)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(filteredSessions) { session in
                    AlbumCell(session: session) {
                        sessionForReview = session
                    }
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingMD)
        }
    }

    private var emptyState: some View {
        VStack(spacing: ProofTheme.spacingMD) {
            Spacer()

            Text("0")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(ProofTheme.inkPrimary.opacity(0.5))

            Text("sessions in \(monthLabel)")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(ProofTheme.inkSoft)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AlbumCell: View {
    let session: PhotoSession
    let onTap: () -> Void

    @State private var selectedPoseIndex: Int = 0

    private var poses: [Pose] {
        Pose.allCases.filter { session.photo(for: $0) != nil }
    }

    private var dateLabel: String {
        session.date.formatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * (213.0 / 120.0)

            ZStack(alignment: .bottom) {
                if poses.isEmpty {
                    placeholderImage
                        .frame(width: width, height: height)
                } else {
                    TabView(selection: $selectedPoseIndex) {
                        ForEach(Array(poses.enumerated()), id: \.offset) { index, pose in
                            if let image = session.photo(for: pose) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: width, height: height)
                                    .clipped()
                                    .tag(index)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: width, height: height)
                }

                VStack(spacing: 4) {
                    datePill
                    pageDots
                }
                .padding(.bottom, 8)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session on \(dateLabel), \(poses.count) of 3 poses")
            .accessibilityAddTraits(.isButton)
        }
        .aspectRatio(120.0 / 213.0, contentMode: .fit)
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(ProofTheme.paperLo.opacity(0.6))
    }

    private var datePill: some View {
        Text(dateLabel)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(ProofTheme.overlayText)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(Array(Pose.allCases.enumerated()), id: \.offset) { index, _ in
                let hasPhoto = session.photo(for: Pose.allCases[index]) != nil
                Circle()
                    .fill(ProofTheme.overlayText.opacity(hasPhoto ? (index == selectedPoseIndex ? 1.0 : 0.3) : 0.1))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

/// Backward-compat alias so any remaining references to HistoryView resolve to AlbumsView.
typealias HistoryView = AlbumsView

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

#Preview {
    AlbumsView()
        .modelContainer(for: PhotoSession.self, inMemory: true)
}
