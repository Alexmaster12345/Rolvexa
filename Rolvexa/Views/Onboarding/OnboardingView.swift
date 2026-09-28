import SwiftUI

struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    Button("Skip") {}
                        .foregroundStyle(.secondary)
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.gradient)
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tell us your story, we'll build your future")
                        .font(.title2.bold())

                    Text("Share your experience and the job you want. Rolvexa's AI builds, analyzes, and improves a tailored application kit — ready to send.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Capsule().fill(Color.indigo).frame(width: 28, height: 6)
                    Circle().fill(Color.indigo.opacity(0.2)).frame(width: 6, height: 6)
                    Circle().fill(Color.indigo.opacity(0.2)).frame(width: 6, height: 6)
                }

                Text("HOW DO YOU WANT TO START?")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    OnboardingOptionCard(
                        icon: "arrow.up.doc.fill",
                        title: "Upload my resume",
                        subtitle: "Get an instant score and AI tips to improve it",
                        highlighted: true
                    ) {
                        appState.buildSource = .upload
                        router.push(.resumeUpload)
                    }

                    OnboardingOptionCard(
                        icon: "pencil",
                        title: "Write my resume",
                        subtitle: "Answer a few prompts and let AI build it from scratch",
                        highlighted: false
                    ) {
                        appState.buildSource = .write
                        router.push(.inputExperience)
                    }
                }

                Button("I already have an account") {}
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        #if os(iOS)
        .navigationBarBackButtonHidden()
        #endif
    }
}

private struct OnboardingOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(Color.indigo)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlighted ? Color.indigo : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        OnboardingView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
