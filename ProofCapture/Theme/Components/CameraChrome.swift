import SwiftUI

struct CameraFrame: View {
    enum BorderState: Equatable {
        case hidden
        case neutral
        case almost
        case ready
    }

    let borderState: BorderState

    var body: some View {
        RoundedRectangle(cornerRadius: ProofTheme.cameraFrameRadius)
            .stroke(strokeColor, lineWidth: strokeWidth)
            .padding(.top, 44)
            .padding(.bottom, 112)
            .opacity(borderState == .hidden ? 0 : 1)
            .animation(.easeInOut(duration: ProofTheme.animationDefault), value: borderState)
            .allowsHitTesting(false)
    }

    private var strokeColor: Color {
        switch borderState {
        case .hidden:
            return .clear
        case .neutral:
            return ProofTheme.borderNeutral
        case .almost:
            return ProofTheme.borderAlmost
        case .ready:
            return ProofTheme.borderReady
        }
    }

    private var strokeWidth: CGFloat {
        switch borderState {
        case .hidden:
            return 0
        case .neutral:
            return ProofTheme.borderWidthNeutral
        case .almost:
            return ProofTheme.borderWidthAlmost
        case .ready:
            return ProofTheme.borderWidthReady
        }
    }
}

struct CameraScrim: View {
    enum Position {
        case top
        case bottom
    }

    let position: Position

    var body: some View {
        VStack {
            if position == .top {
                LinearGradient(
                    colors: [Color.black.opacity(0.60), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 92)
                Spacer()
            } else {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 112)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CaptureButton: View {
    let action: () -> Void
    var disabled = false
    var loading = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(Color.white)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
                if loading {
                    ProgressView()
                        .tint(ProofTheme.inkPrimary)
                }
            }
            .opacity(disabled ? 0.4 : 1.0)
        }
        .buttonStyle(CaptureButtonPressStyle())
        .disabled(disabled)
    }
}

private struct CaptureButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: ProofTheme.animationFast), value: configuration.isPressed)
    }
}
