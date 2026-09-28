import SwiftUI

/// The "Polishing your resume" loading modal shown while `ResumeAnalysisEngine`'s fix pipeline
/// (deterministic word-swaps + the on-device AI rewrite) runs — shared by every "Fix It For Me"
/// entry point so the wait looks the same regardless of which screen triggered it.
struct FixingResumeOverlay: View {
    var progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.indigo.opacity(0.2), lineWidth: 6)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.indigo)
                }
                .frame(width: 88, height: 88)

                VStack(spacing: 8) {
                    Text("Polishing your resume")
                        .font(.title3.bold())
                    Text("AI is rewriting bullet points and optimizing for ATS compatibility…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: progress)
                    .tint(.indigo)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.appPageBackground))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 32)
        }
    }
}
