import SwiftUI

// Large left-aligned uppercase instruction block for pre-capture screens.
// Matches frame 390:2664. 48pt .medium, tracking 2, line-height 50.

struct InstructionHero: View {
    let lines: [String]
    var color: Color = ProofTheme.paperHi

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            ForEach(lines, id: \.self) { block in
                Text(block)
                    .font(.system(size: 48, weight: .medium))
                    .tracking(2)
                    .lineSpacing(2)
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
    }
}

// Apple HIG-style progress bar used beneath InstructionHero in the
// pre-capture instruction flow. 6pt track, cream fill on gray 20%.

struct ProofProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 120/255).opacity(0.2))
                Capsule()
                    .fill(ProofTheme.paperHi)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .animation(.easeInOut(duration: ProofTheme.animationDefault), value: progress)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

#Preview("InstructionHero + ProgressBar") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            InstructionHero(lines: [
                "PLACE YOUR PHONE DOWN",
                "STAND 2M BACK",
                "TRY AND BE UNDER A LIGHT"
            ])
            Spacer()
            ProofProgressBar(progress: 0.6)
                .padding(.bottom, 29)
        }
    }
}
