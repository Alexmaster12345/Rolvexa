import SwiftUI

struct InputExperienceView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var newSkill = ""
    @FocusState private var focusedField: Field?

    /// Every focusable field on this form, in on-screen order. A field that's currently covered
    /// by the keyboard can never be *tapped* directly — the touch hits the keyboard, not the
    /// field underneath it, so any typed text silently lands wherever focus already was. That's
    /// a physical constraint, not something scroll-on-focus-change alone can fix: moving between
    /// fields has to be possible without tapping a potentially-hidden one, hence the
    /// Previous/Next keyboard toolbar below, which can always reach the next field.
    private enum Field: Hashable, CaseIterable {
        case fullName, currentRole, email, phone, location, newSkill, education, workHistory
    }

    private func moveFocus(by offset: Int) {
        guard let current = focusedField, let index = Field.allCases.firstIndex(of: current) else { return }
        let newIndex = index + offset
        guard Field.allCases.indices.contains(newIndex) else { return }
        focusedField = Field.allCases[newIndex]
    }

    var body: some View {
        @Bindable var appState = appState

        ScrollViewReader { proxy in
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
                        .focused($focusedField, equals: .fullName)
                }
                .id(Field.fullName)

                LabeledField(title: "Current Role / Most Recent Title") {
                    TextField("e.g. Senior Product Designer", text: $appState.experience.currentRole)
                        .textFieldStyle(.roundedInput)
                        .focused($focusedField, equals: .currentRole)
                }
                .id(Field.currentRole)

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
                            .focused($focusedField, equals: .email)
                        TextField("Phone", text: $appState.experience.phone)
                            .textFieldStyle(.roundedInput)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                            .focused($focusedField, equals: .phone)
                            .id(Field.phone)
                        TextField("Location (e.g. San Francisco, CA)", text: $appState.experience.location)
                            .textFieldStyle(.roundedInput)
                            .focused($focusedField, equals: .location)
                            .id(Field.location)
                    }
                }
                .id(Field.email)

                LabeledField(title: "Key Skills") {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayoutSkills(skills: appState.experience.skills) { skill in
                            appState.experience.skills.removeAll { $0 == skill }
                        }
                        HStack {
                            TextField("Add skill", text: $newSkill)
                                .textFieldStyle(.roundedInput)
                                .focused($focusedField, equals: .newSkill)
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
                .id(Field.newSkill)

                LabeledField(title: "Education") {
                    TextEditor(text: $appState.experience.education)
                        .frame(height: 80)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                        .focused($focusedField, equals: .education)
                }
                .id(Field.education)

                LabeledField(title: "Professional Experience") {
                    TextEditor(text: $appState.experience.workHistorySummary)
                        .frame(height: 100)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                        .focused($focusedField, equals: .workHistory)
                }
                .id(Field.workHistory)

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

                // Extra scroll room so any field can still be scrolled clear of the keyboard —
                // without this, a field near the bottom has nowhere left to scroll to and the
                // keyboard permanently covers it.
                Color.clear.frame(height: 250)
            }
            .padding(20)
        }
        .onChange(of: focusedField) { _, newValue in
            guard let newValue else { return }
            withAnimation {
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    moveFocus(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(focusedField == Field.allCases.first)

                Button {
                    moveFocus(by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(focusedField == Field.allCases.last)

                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
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
