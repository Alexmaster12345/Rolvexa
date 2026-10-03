import SwiftUI

struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    /// Read when the screen appears rather than on every body evaluation — reading it decodes
    /// every saved record off disk.
    @State private var saved: [ResumeLibrary.Summary] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    // Skips the explainer rather than doing nothing, which is what it did
                    // before. Writing from scratch is the quickest route into the product.
                    Button("Skip") {
                        appState.buildSource = .write
                        router.push(.inputExperience)
                    }
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

                    // Always present, so the three ways to start are visible from the first
                    // launch — but inert and clearly labelled when there is nothing saved yet.
                    // Hiding it entirely made the screen look different on first run; offering
                    // a live "continue your resume" with nothing behind it would be a promise
                    // the app can't keep.
                    OnboardingOptionCard(
                        icon: "folder",
                        title: "Saved resume",
                        subtitle: savedSubtitle,
                        highlighted: false,
                        isEnabled: !saved.isEmpty
                    ) {
                        router.push(.myResumes)
                    }
                }

                // The app's central claim is that nothing leaves the device, so the page that
                // spells out exactly what that does and doesn't cover is reachable before the
                // user hands over a resume — not buried in a settings screen afterwards.
                Button("Privacy & Terms") {
                    router.push(.legalAndPrivacy)
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(Color.indigo)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .padding(20)
        }
        // `onAppear` rather than `task`, so popping back from the library picks up a resume
        // that was just deleted or created there.
        .onAppear { saved = ResumeLibrary.summaries() }
        #if os(iOS)
        .navigationBarBackButtonHidden()
        #endif
    }

    /// Says how much is stored and when it last changed, rather than just "continue" — the
    /// difference between one resume and five is the thing worth knowing before tapping.
    private var savedSubtitle: String {
        guard let newest = saved.first else {
            return "Nothing saved yet — your progress is kept automatically as you go"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: newest.updatedAt, relativeTo: Date())
        return saved.count == 1
            ? "Continue where you left off — edited \(when)"
            : "\(saved.count) resumes saved — last edited \(when)"
    }
}

private struct OnboardingOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let highlighted: Bool
    /// A card can be shown but not yet usable — "Saved resume" before anything is saved.
    /// Dimmed and non-tappable rather than hidden, so the set of options doesn't change shape
    /// between a first launch and a later one.
    var isEnabled: Bool = true
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityHint(isEnabled ? "" : "Unavailable until you have a saved draft")
    }
}

#Preview("Nothing saved") {
    ResumeLibrary.deleteAll()
    return NavigationStack {
        OnboardingView()
    }
    .environment(AppRouter())
    .environment(AppState())
}

#Preview("With saved resumes") {
    ResumeLibrary.deleteAll()
    var experience = ExperienceInput()
    experience.fullName = "Jane Doe"
    experience.currentRole = "Operations Manager"
    ResumeLibrary.save(
        ResumeLibrary.SavedResume(
            experience: experience,
            jobTarget: JobTarget(),
            templateStyle: .modernEdge,
            createdAt: Date().addingTimeInterval(-7_200),
            updatedAt: Date().addingTimeInterval(-7_200),
            contentFingerprint: ResumeLibrary.fingerprint(
                experience: experience, jobTarget: JobTarget()
            )
        ),
        modifiedAt: Date().addingTimeInterval(-7_200)
    )
    return NavigationStack {
        OnboardingView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
