import SwiftUI

// Rounded inner frame that hosts the camera feed. Border color + width
// signals readiness. Replaces the v11 full-bleed edge glow.
// Matches Subtract masks in Figma frames 390:2750 and 406:735.

struct CameraFrame<Content: View>: View {
    enum BorderState: Equatable {
        case hidden
        case neutral
        case almost
        case ready
    }

    let borderState: BorderState
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        borderState: BorderState = .neutral,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.borderState = borderState
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(border)
    }

    @ViewBuilder
    private var border: some View {
        if borderState != .hidden {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(color, lineWidth: width)
                .animation(.easeInOut(duration: ProofTheme.animationDefault), value: borderState)
        }
    }

    private var color: Color {
        switch borderState {
        case .hidden:  return .clear
        case .neutral: return ProofTheme.borderNeutral
        case .almost:  return ProofTheme.borderAlmost
        case .ready:   return ProofTheme.borderReady
        }
    }

    private var width: CGFloat {
        switch borderState {
        case .hidden:  return 0
        case .neutral: return 2
        case .almost:  return 3
        case .ready:   return 8
        }
    }
}

// Top + bottom dark gradient scrims over the camera feed. Protects
// status bar + capture button legibility without a flat black bar.
// Matches the Subtract gradient SVGs in frame 389:2406.

struct CameraScrim: View {
    enum Edge { case top, bottom }

    let edge: Edge
    var height: CGFloat

    init(_ edge: Edge, height: CGFloat? = nil) {
        self.edge = edge
        self.height = height ?? (edge == .top ? 92 : 112)
    }

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [.black.opacity(0.55), .black.opacity(0)]
                : [.black.opacity(0), .black.opacity(0.65)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

// iOS-native capture CTA. 88pt outer ring + inner white circle.
// Placed in the bottom CameraScrim during the neutral capture state.

struct CaptureButton: View {
    let action: () -> Void
    var isEnabled: Bool = true
    var isBusy: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(.white)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)

                if isBusy {
                    ProgressView()
                        .tint(ProofTheme.inkPrimary)
                }
            }
        }
        .buttonStyle(CapturePressStyle())
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled && !isBusy ? 1 : 0.4)
        .accessibilityLabel("Capture")
    }
}

private struct CapturePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: ProofTheme.animationFast), value: configuration.isPressed)
    }
}

private let previewStates: [CameraFrame<Color>.BorderState] = [.neutral, .almost, .ready]

#Preview("CameraFrame states") {
    VStack(spacing: 16) {
        ForEach(previewStates, id: \.self) { state in
            CameraFrame(borderState: state) {
                Color.gray
            }
            .frame(width: 200, height: 300)
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("CaptureButton + scrim") {
    ZStack(alignment: .bottom) {
        Color.gray.ignoresSafeArea()
        CameraScrim(.bottom)
        VStack {
            CaptureButton(action: {})
                .padding(.bottom, 24)
        }
    }
}
