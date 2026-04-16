import AVFoundation
import SwiftUI

/// Onboarding step 3 — dark world. Voice picker as glass capsule pair, primary CTA
/// requesting camera permission.
struct PermissionStep: View {
    @AppStorage("userGender") private var genderRaw = 0
    let onComplete: () -> Void

    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            VStack(spacing: ProofTheme.spacingSM) {
                Text("PERMISSIONS")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.textTertiary)

                Text("Almost ready")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi)
                    .accessibilityAddTraits(.isHeader)

                Text("Camera access lets Checkd guide and save your check-ins.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Spacer()

            VStack(spacing: ProofTheme.spacingMD) {
                Text("GUIDE VOICE")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.textTertiary)

                HStack(spacing: 12) {
                    voicePill(label: "Male", value: 0)
                    voicePill(label: "Female", value: 1)
                }
            }
            .padding(.horizontal, ProofTheme.spacingLG)

            Spacer()

            if permissionDenied {
                VStack(spacing: ProofTheme.spacingSM) {
                    Text("Camera access required.\nEnable it in Settings.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ProofTheme.statusPoor)
                        .multilineTextAlignment(.center)

                    Button {
                        ProofTheme.hapticLight()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ProofTheme.paperHi)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .modifier(ProofTheme.SecondaryButtonBackground())
                    }
                    .padding(.horizontal, ProofTheme.spacingLG)
                    .accessibilityLabel("Open Settings to grant camera access")
                }
                .padding(.bottom, ProofTheme.spacingMD)
            }

            Button {
                ProofTheme.hapticLight()
                Task { await requestCameraAccess() }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .modifier(ProofTheme.PrimaryButtonBackground())
            }
            .padding(.horizontal, ProofTheme.spacingLG)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Grant camera access and continue")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .proofDynamicType()
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard permissionDenied else { return }
            Task { await recheckPermission() }
        }
    }

    private func requestCameraAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                ProofTheme.hapticSuccess()
                onComplete()
            } else {
                permissionDenied = true
            }
        } else if status == .authorized {
            ProofTheme.hapticSuccess()
            onComplete()
        } else {
            permissionDenied = true
        }
    }

    private func recheckPermission() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            permissionDenied = false
            ProofTheme.hapticSuccess()
            onComplete()
        }
    }

    private func voicePill(label: String, value: Int) -> some View {
        let isSelected = genderRaw == value
        return Button {
            ProofTheme.hapticLight()
            withAnimation(.easeInOut(duration: 0.2)) {
                genderRaw = value
            }
        } label: {
            HStack(spacing: ProofTheme.spacingSM) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? ProofTheme.background : ProofTheme.paperHi)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProofTheme.background)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(voicePillBackground(isSelected: isSelected))
        }
        .accessibilityLabel("\(label) voice")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func voicePillBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule().fill(ProofTheme.paperHi)
        } else if #available(iOS 26, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(ProofTheme.surface)
                .overlay(Capsule().stroke(ProofTheme.paperHi.opacity(0.08), lineWidth: 1))
        }
    }
}
