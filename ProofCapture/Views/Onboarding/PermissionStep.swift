import AVFoundation
import SwiftUI

struct PermissionStep: View {
    @AppStorage("userGender") private var genderRaw = 0
    let onComplete: () -> Void

    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Almost ready")
                .proofFont(24, weight: .light, relativeTo: .title2)
                .foregroundStyle(ProofTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("We need camera access to capture\nyour progress photos.")
                .proofFont(15, weight: .light, relativeTo: .body)
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, ProofTheme.spacingMD)

            Spacer()

            // Voice choice
            VStack(spacing: ProofTheme.spacingSM) {
                Text("Guide voice")
                    .proofFont(13, weight: .light, relativeTo: .footnote)
                    .foregroundStyle(ProofTheme.textTertiary)

                HStack(spacing: ProofTheme.spacingMD) {
                    voiceButton(label: "Male", value: 0)
                    voiceButton(label: "Female", value: 1)
                }
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            if permissionDenied {
                VStack(spacing: ProofTheme.spacingMD) {
                    Text("Camera access is required.\nEnable it in Settings to continue.")
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.statusPoor)
                        .multilineTextAlignment(.center)

                    Button {
                        ProofTheme.hapticLight()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                    }
                    .buttonStyle(ProofTheme.ProofSecondaryButtonStyle())
                    .padding(.horizontal, ProofTheme.spacingXL)
                    .accessibilityLabel("Open Settings to grant camera access")
                }
                .padding(.bottom, ProofTheme.spacingMD)
            }

            Button(action: {
                ProofTheme.hapticLight()
                Task { await requestCameraAccess() }
            }) {
                Text("Continue")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Grant camera access and continue")
        }
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

    private func voiceButton(label: String, value: Int) -> some View {
        let isSelected = genderRaw == value
        return Button {
            ProofTheme.hapticLight()
            withAnimation(.easeInOut(duration: 0.2)) {
                genderRaw = value
            }
        } label: {
            HStack(spacing: ProofTheme.spacingSM) {
                Text(label)
                    .proofFont(15, weight: .light, relativeTo: .body)
                    .foregroundStyle(isSelected ? ProofTheme.background : ProofTheme.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(ProofTheme.background)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(isSelected ? ProofTheme.accent : ProofTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                    .strokeBorder(isSelected ? Color.clear : ProofTheme.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .accessibilityLabel("\(label) voice")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
