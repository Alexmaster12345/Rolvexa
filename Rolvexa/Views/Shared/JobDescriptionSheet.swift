import SwiftUI

/// Paste-the-posting sheet, backing `AppState.jobTarget.descriptionText`.
///
/// Reachable from the Application Kit screen so both build sources get to it — the upload flow
/// never passes through the "write my resume" form where the target role is entered.
struct JobDescriptionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste the job posting and Rolvexa will compare it against your resume — which required skills you already cover, and which are missing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $appState.jobTarget.descriptionText)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))

                // Analysis needs enough text to pull requirements out of; saying so up front
                // beats returning a confident score built from two lines.
                if !appState.jobTarget.descriptionText.isEmpty, appState.jobFitAnalysis == nil {
                    Label(
                        "Add a bit more of the posting — there isn't enough here to compare against yet.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Stays on your device, like everything else.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .navigationTitle("Job Description")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { appState.jobTarget.descriptionText = "" }
                        .tint(.red)
                        .disabled(appState.jobTarget.descriptionText.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    JobDescriptionSheet()
        .environment(AppState())
}
