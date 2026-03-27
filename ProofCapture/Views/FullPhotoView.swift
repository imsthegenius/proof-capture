import SwiftUI

struct FullPhotoView: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(title)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
    }
}
