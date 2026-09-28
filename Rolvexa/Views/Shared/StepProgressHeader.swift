import SwiftUI

struct StepProgressHeader: View {
    let step: Int
    let totalSteps: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer()
                Text("Step \(step) of \(totalSteps)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(1...totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.indigo : Color.indigo.opacity(0.15))
                        .frame(height: 5)
                }
            }
        }
    }
}

#Preview {
    StepProgressHeader(step: 2, totalSteps: 4).padding()
}
