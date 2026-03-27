import SwiftUI
import AVFoundation

struct PermissionStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Camera access")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Proof needs your camera to capture\nprogress photos. Photos stay on your device\nand are backed up to your private cloud.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, ProofTheme.spacingMD)

            Spacer()

            Button(action: {
                Task {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .notDetermined {
                        await AVCaptureDevice.requestAccess(for: .video)
                    }
                    ProofTheme.hapticSuccess()
                    onComplete()
                }
            }) {
                Text("Allow camera")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }
}
