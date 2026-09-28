import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var isAnimatingDots = false

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("Rolvexa")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your AI copilot for landing the job")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()
                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white)
                            .frame(width: 7, height: 7)
                            .opacity(isAnimatingDots ? 1 : 0.3)
                            .scaleEffect(isAnimatingDots ? 1.3 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimatingDots
                            )
                    }
                }
                .onAppear { isAnimatingDots = true }

                Text("Preparing your experience…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
