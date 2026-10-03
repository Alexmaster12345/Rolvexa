import SwiftUI

/// The saved-resume library.
///
/// Follows the supplied design — searchable list, a score chip per row, a "Create New Resume"
/// action — but only shows what the app can actually back. Two things from the design are
/// deliberately absent, and the reasons are the same ones that kept Cookie Policy and Delete
/// Account off the Legal & Privacy screen:
///
/// - **The "Applied" status badge.** Rolvexa never sends an application and is never told that
///   you did, so it cannot know. A badge claiming otherwise would be a guess printed as a fact.
/// - **The Home / Jobs / Analytics / Profile tab bar.** There is no job tracking and no
///   analytics. Tabs leading to empty screens advertise features that don't exist.
///
/// The score chip is shown only while the stored score still matches the resume's current
/// content — see ``ResumeLibrary/ScoreStamp``. A resume edited since it was last scored shows
/// no number rather than the old one.
struct MyResumesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var summaries: [ResumeLibrary.Summary] = []
    @State private var query = ""
    @State private var pendingDeletion: ResumeLibrary.Summary?

    private var visible: [ResumeLibrary.Summary] {
        summaries.filter { $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if summaries.isEmpty {
                    emptyState
                } else {
                    searchField

                    if visible.isEmpty {
                        noMatches
                    } else {
                        VStack(spacing: 12) {
                            ForEach(visible) { summary in
                                resumeCard(summary)
                            }
                        }
                    }
                }

                createButton
            }
            .padding(20)
        }
        .navigationTitle("My Resumes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { summaries = ResumeLibrary.summaries() }
        .confirmationDialog(
            pendingDeletion.map { "Delete \"\($0.title)\"?" } ?? "Delete this resume?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { summary in
            Button("Delete", role: .destructive) {
                appState.deleteResume(id: summary.id)
                summaries = ResumeLibrary.summaries()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes it from this device. It can't be undone, and there is no copy anywhere else.")
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by role, employer or skill", text: $query)
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private func resumeCard(_ summary: ResumeLibrary.Summary) -> some View {
        Button {
            appState.buildSource = .write
            appState.openResume(id: summary.id)
            router.push(.inputExperience)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if !summary.subtitle.isEmpty {
                            Text(summary.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 8)

                    if let score = summary.score {
                        scoreChip(score)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(Self.editedDescription(for: summary.updatedAt))
                        .font(.caption)

                    Spacer()

                    Button {
                        pendingDeletion = summary
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(summary.title)")
                }
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appCardBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private func scoreChip(_ score: Int) -> some View {
        let tint: Color = score >= 85 ? .green : (score >= 70 ? .indigo : .orange)
        return Text("\(score)%")
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .accessibilityLabel("Resume score \(score) percent")
    }

    private var createButton: some View {
        Button {
            appState.buildSource = .write
            appState.startNewResume()
            router.push(.inputExperience)
        } label: {
            Label("Create New Resume", systemImage: "plus")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.gradient)
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 34))
                .foregroundStyle(Color.indigo.opacity(0.6))
            Text("No resumes yet")
                .font(.subheadline.bold())
            Text("Resumes you work on are saved here automatically when you leave the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noMatches: some View {
        Text("No resume matches \"\(query)\".")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }

    /// "Edited 2 hours ago" — concrete enough to tell two sessions apart.
    private static func editedDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Edited \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

#Preview("With saved resumes") {
    ResumeLibrary.deleteAll()
    for (role, company, skills, score, age) in [
        ("Senior Product Designer", "Acme Corp", ["Figma", "Prototyping"], 92, 3_600.0),
        ("Operations Manager", "Globex", ["Scheduling", "Budgeting"], 78, 172_800.0),
        ("Facility Property Manager", "Initech", ["Vendor Management"], nil, 864_000.0)
    ] as [(String, String, [String], Int?, Double)] {
        var experience = ExperienceInput()
        experience.fullName = "Jane Doe"
        experience.currentRole = role
        experience.skills = skills
        var target = JobTarget()
        target.title = role
        target.company = company
        let fingerprint = ResumeLibrary.fingerprint(experience: experience, jobTarget: target)
        ResumeLibrary.save(
            ResumeLibrary.SavedResume(
                experience: experience,
                jobTarget: target,
                templateStyle: .modernEdge,
                createdAt: Date().addingTimeInterval(-age),
                updatedAt: Date().addingTimeInterval(-age),
                contentFingerprint: fingerprint,
                score: score.map {
                    ResumeLibrary.ScoreStamp(
                        value: $0, fingerprint: fingerprint, computedAt: Date()
                    )
                }
            ),
            modifiedAt: Date().addingTimeInterval(-age)
        )
    }
    return NavigationStack { MyResumesView() }
        .environment(AppRouter())
        .environment(AppState())
}

#Preview("Empty") {
    ResumeLibrary.deleteAll()
    return NavigationStack { MyResumesView() }
        .environment(AppRouter())
        .environment(AppState())
}
