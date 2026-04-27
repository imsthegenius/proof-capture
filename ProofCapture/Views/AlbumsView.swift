import SwiftData
import SwiftUI

struct AlbumsView: View {
    @Query(
        filter: #Predicate<PhotoSession> { $0.isComplete },
        sort: \PhotoSession.date,
        order: .reverse
    ) private var sessions: [PhotoSession]

    @Binding var tabSelection: LiquidGlassTab

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ProofTheme.paperHi.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 11)
                    .padding(.top, 16)

                DatePill(text: currentMonthTitle) { }
                    .padding(.horizontal, 9)
                    .padding(.top, 16)

                if sessions.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(sessions) { session in
                                NavigationLink(destination: ReviewView(session: session)) {
                                    PhotoTileView(
                                        image: session.photo(for: .front),
                                        dateText: ordinalDateText(for: session.date),
                                        activePoseIndex: 0
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 16)
                        .padding(.bottom, 132)
                    }
                }
            }

            LiquidGlassTabBar(selection: $tabSelection)
                .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .proofDynamicType()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Albums")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(ProofTheme.inkPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ProofTheme.inkPrimary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Profile and settings")
        }
    }

    private var emptyState: some View {
        VStack(spacing: ProofTheme.spacingSM) {
            Text("0")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(ProofTheme.inkPrimary)
            Text("check-ins")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ProofTheme.inkSoft)
            Text("Your guided progress photos will appear here.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ProofTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, ProofTheme.spacingSM)
        }
        .padding(.horizontal, ProofTheme.spacingXL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No check-ins. Your guided progress photos will appear here.")
    }

    private var currentMonthTitle: String {
        Date().formatted(.dateTime.month(.wide))
    }

    private func ordinalDateText(for date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.component(.day, from: date)
        let suffix: String
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        let month = date.formatted(.dateTime.month(.wide))
        return "\(day)\(suffix) \(month)"
    }
}
