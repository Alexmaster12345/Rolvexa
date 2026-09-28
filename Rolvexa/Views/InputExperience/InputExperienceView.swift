import SwiftUI

struct InputExperienceView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var newSkill = ""

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepProgressHeader(step: 1, totalSteps: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tell us about your experience")
                        .font(.title2.bold())
                    Text("This helps our AI understand your background")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LabeledField(title: "Full Name") {
                    TextField("e.g. Jamie Chen", text: $appState.experience.fullName)
                        .textFieldStyle(.roundedInput)
                }

                LabeledField(title: "Current Role / Most Recent Title") {
                    TextField("e.g. Senior Product Designer", text: $appState.experience.currentRole)
                        .textFieldStyle(.roundedInput)
                }

                LabeledField(title: "Years of Experience") {
                    Picker("", selection: $appState.experience.yearsOfExperience) {
                        ForEach(["0–1 years", "2–4 years", "5–7 years", "8+ years"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                }

                LabeledField(title: "Contact Information") {
                    VStack(spacing: 10) {
                        TextField("Email", text: $appState.experience.email)
                            .textFieldStyle(.roundedInput)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                        TextField("Phone", text: $appState.experience.phone)
                            .textFieldStyle(.roundedInput)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                        TextField("Location (e.g. San Francisco, CA)", text: $appState.experience.location)
                            .textFieldStyle(.roundedInput)
                    }
                }

                LabeledField(title: "Key Skills") {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayoutSkills(skills: appState.experience.skills) { skill in
                            appState.experience.skills.removeAll { $0 == skill }
                        }
                        HStack {
                            TextField("Add skill", text: $newSkill)
                                .textFieldStyle(.roundedInput)
                            Button("Add") {
                                let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                appState.experience.skills.append(trimmed)
                                newSkill = ""
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo)
                        }
                    }
                }

                LabeledField(title: "Education") {
                    TextEditor(text: $appState.experience.education)
                        .frame(height: 80)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                }

                LabeledField(title: "Professional Experience") {
                    TextEditor(text: $appState.experience.workHistorySummary)
                        .frame(height: 100)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                }

                if !isFormValid {
                    Text("Fill in every field above to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    router.push(.resumeTemplates)
                } label: {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.primaryGradient)
                .disabled(!isFormValid)
            }
            .padding(20)
        }
    }

    /// Every field on this screen is required before moving on — a resume with a blank contact
    /// field or no experience at all isn't something worth generating a kit from.
    private var isFormValid: Bool {
        let experience = appState.experience
        return !experience.fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.currentRole.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.email.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.phone.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.location.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.education.trimmingCharacters(in: .whitespaces).isEmpty
            && !experience.workHistorySummary.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

#Preview {
    NavigationStack {
        InputExperienceView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
