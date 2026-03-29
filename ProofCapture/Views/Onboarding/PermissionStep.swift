import SwiftUI
import AVFoundation

struct PermissionStep: View {
    @AppStorage("userGender") private var genderRaw = 0
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Almost ready")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("We need camera access to capture\nyour progress photos.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, ProofTheme.spacingMD)

            Spacer()

            // Voice choice
            VStack(spacing: ProofTheme.spacingSM) {
                Text("Guide voice")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)

                HStack(spacing: ProofTheme.spacingMD) {
                    voiceButton(label: "Male", value: 0)
                    voiceButton(label: "Female", value: 1)
                }
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            if permissionDenied {
                Text("Camera access is required.\nGo to Settings → Proof Capture → Camera.")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.statusPoor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, ProofTheme.spacingMD)
            }

            Button(action: {
                ProofTheme.hapticLight()
                Task {
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
            }) {
                Text("Continue")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Grant camera access and continue")
        }
    }

    @State private var permissionDenied = false

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
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(isSelected ? ProofTheme.background : ProofTheme.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(ProofTheme.background)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
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
