import SwiftUI

/// Settings — cream paper world. Reached from the Albums profile icon and the
/// Camera tab gear. Same paper gradient and typography vocabulary as AlbumsView,
/// rows rendered as glass capsule pickers.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userGender") private var genderRaw = 0
    @AppStorage("guidanceMode") private var guidanceMode = 0

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            paperBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: ProofTheme.spacingXL) {
                    Text("Settings")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(ProofTheme.inkPrimary)
                        .padding(.top, ProofTheme.spacingMD)

                    section(title: "GUIDE VOICE") {
                        pillRow(["Male", "Female"], selectedIndex: genderRaw) { genderRaw = $0 }
                    }

                    section(title: "GUIDANCE") {
                        pillRow(["Voice", "Text"], selectedIndex: guidanceMode) { guidanceMode = $0 }
                    }

                    section(title: "PRIVACY") {
                        VStack(alignment: .leading, spacing: 12) {
                            privacyRow("Photos stored on-device only")
                            privacyRow("Cloud backup encrypted to your Apple ID")
                            privacyRow("No sharing, no analytics on photo content")
                        }
                    }

                    Button {
                        Task {
                            await authManager.signOut()
                            dismiss()
                        }
                    } label: {
                        Text("Sign out")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ProofTheme.statusPoor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(signOutBackground)
                    }
                    .accessibilityLabel("Sign out of your account")

                    VStack(spacing: 4) {
                        Text("Checkd")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ProofTheme.inkSoft)
                        Text("v\(appVersion)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(ProofTheme.inkSoft.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, ProofTheme.spacingMD)
                }
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, 100) // tab bar clearance
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .proofDynamicType()
    }

    private var paperBackground: some View {
        LinearGradient(
            colors: [ProofTheme.paperHi, ProofTheme.paperLo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(2.5)
                .foregroundStyle(ProofTheme.inkSoft.opacity(0.7))

            content()
        }
    }

    private func pillRow(_ options: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                Button {
                    ProofTheme.hapticLight()
                    withAnimation(.easeInOut(duration: ProofTheme.animationFast)) {
                        onSelect(index)
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(index == selectedIndex ? ProofTheme.paperHi : ProofTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(index == selectedIndex ? ProofTheme.inkPrimary : Color.clear)
                                .padding(3)
                        )
                }
                .accessibilityLabel(label)
                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
            }
        }
        .background(pillRowBackground)
    }

    @ViewBuilder
    private var pillRowBackground: some View {
        if #available(iOS 26, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(ProofTheme.paperHi.opacity(0.6))
                .overlay(Capsule().stroke(ProofTheme.inkSoft.opacity(0.1), lineWidth: 1))
        }
    }

    private func privacyRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ProofTheme.statusGood)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ProofTheme.inkPrimary.opacity(0.85))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private var signOutBackground: some View {
        if #available(iOS 26, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(ProofTheme.paperHi.opacity(0.6))
                .overlay(Capsule().stroke(ProofTheme.statusPoor.opacity(0.2), lineWidth: 1))
        }
    }
}
