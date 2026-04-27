import SwiftUI

struct InstructionHero: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 48, weight: .medium))
                    .tracking(2)
                    .lineSpacing(2)
                    .textCase(.uppercase)
                    .foregroundStyle(ProofTheme.paperHi)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, ProofTheme.spacingLG)
        .accessibilityElement(children: .combine)
    }
}

struct ProofProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 6)
                Capsule()
                    .fill(ProofTheme.paperHi)
                    .frame(width: max(0, min(1, progress)) * geometry.size.width, height: 6)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(max(0, min(1, progress)) * 100)) percent")
    }
}
