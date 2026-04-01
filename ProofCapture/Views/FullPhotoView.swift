import SwiftUI

struct FullPhotoView: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    doubleTapZoom()
                }
                .accessibilityLabel(title)
                .accessibilityHint("Double tap to zoom, pinch to adjust zoom level")
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ProofTheme.overlayText)
                    .frame(width: 44, height: 44)
                    .background(ProofTheme.overlayPill)
                    .clipShape(Circle())
            }
            .padding(.leading, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)
            .accessibilityLabel("Close")
        }
        .onDisappear {
            resetZoom()
        }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale {
                    resetZoom()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - Actions

    private func doubleTapZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        lastScale = minScale
        offset = .zero
        lastOffset = .zero
    }
}
