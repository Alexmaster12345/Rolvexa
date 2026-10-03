import PhotosUI
import SwiftUI

struct InputExperienceView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var newSkill = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoLoadFailed = false
    @FocusState private var focusedField: Field?

    /// Every focusable field on this form. A field that's currently covered by the keyboard can
    /// never be *tapped* directly — the touch hits the keyboard, not the field underneath it, so
    /// any typed text silently lands wherever focus already was. That's a physical constraint,
    /// not something scroll-on-focus-change alone can fix, hence the Previous/Next keyboard
    /// toolbar below, which can always reach the next field.
    ///
    /// The job and school fields repeat, so the order can't be a static `CaseIterable` list —
    /// ``orderedFields`` rebuilds it from the current entries instead.
    private enum Field: Hashable {
        case fullName, currentRole, email, phone, location, linkedIn, portfolio
        case targetTitle, targetCompany, jobDescription, newSkill, summary
        case positionTitle(UUID), positionCompany(UUID), positionLocation(UUID)
        case positionStart(UUID), positionEnd(UUID), positionBullet(UUID, Int)
        case educationDegree(UUID), educationSchool(UUID), educationLocation(UUID), educationDate(UUID)
    }

    /// On-screen order, including every repeated job and school field.
    private var orderedFields: [Field] {
        var fields: [Field] = [
            .fullName, .currentRole, .email, .phone, .location,
            .linkedIn, .portfolio, .targetTitle, .targetCompany, .jobDescription, .newSkill, .summary
        ]
        for position in appState.experience.positions {
            fields.append(contentsOf: [
                .positionTitle(position.id), .positionCompany(position.id), .positionLocation(position.id),
                .positionStart(position.id)
            ])
            if !position.isCurrent { fields.append(.positionEnd(position.id)) }
            fields.append(contentsOf: position.bullets.indices.map { .positionBullet(position.id, $0) })
        }
        for entry in appState.experience.educationEntries {
            fields.append(contentsOf: [
                .educationDegree(entry.id), .educationSchool(entry.id),
                .educationLocation(entry.id), .educationDate(entry.id)
            ])
        }
        return fields
    }

    private func moveFocus(by offset: Int) {
        let fields = orderedFields
        guard let current = focusedField, let index = fields.firstIndex(of: current) else { return }
        let newIndex = index + offset
        guard fields.indices.contains(newIndex) else { return }
        focusedField = fields[newIndex]
    }

    var body: some View {
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

                    photoSection
                    basicsSection
                    contactSection
                    targetSection
                    skillsSection
                    summarySection
                    experienceSection
                    educationSection

                    if !isFormValid {
                        Text(validationMessage)
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
                    .disabled(focusedField == orderedFields.first)

                    Button {
                        moveFocus(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(focusedField == orderedFields.last)

                    Spacer()

                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }

    // MARK: - Sections

    /// The headshot only appears in the Modern Edge template, which is the one with a sidebar to
    /// put it in — hence the hint, so picking a photo and then choosing a different template
    /// isn't a surprise.
    private var photoSection: some View {
        LabeledField(title: "Photo (optional)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    photoThumbnail

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Label(
                                appState.experience.photoData == nil ? "Choose photo" : "Replace photo",
                                systemImage: "person.crop.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)

                        if appState.experience.photoData != nil {
                            Button(role: .destructive) {
                                appState.experience.photoData = nil
                                selectedPhotoItem = nil
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Text("Shown as a circle in the Modern Edge template, on screen and in the downloaded PDF and Word file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if photoLoadFailed {
                    Text("That image couldn't be read. Try a different photo.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(newValue) }
        }
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        if let data = appState.experience.photoData, let image = ResumePhoto.image(from: data) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.appCardBackground)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// Photos hands back bytes rather than a URL, and the raw bytes are a full-resolution camera
    /// image — `ResumePhoto.prepare` crops and shrinks it before it's stored.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ResumePhoto.prepare(from: data) else {
            selectedPhotoItem = nil
            photoLoadFailed = true
            return
        }
        photoLoadFailed = false
        appState.experience.photoData = prepared
    }

    private var basicsSection: some View {
        @Bindable var appState = appState

        return Group {
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
        }
    }

    private var contactSection: some View {
        @Bindable var appState = appState

        return Group {
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

            LabeledField(title: "Links (optional)") {
                VStack(spacing: 10) {
                    TextField("LinkedIn (e.g. linkedin.com/in/jamiechen)", text: $appState.experience.linkedIn)
                        .textFieldStyle(.roundedInput)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .focused($focusedField, equals: .linkedIn)
                    TextField("Portfolio or website", text: $appState.experience.portfolio)
                        .textFieldStyle(.roundedInput)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .focused($focusedField, equals: .portfolio)
                        .id(Field.portfolio)
                }
            }
            .id(Field.linkedIn)
        }
    }

    private var targetSection: some View {
        @Bindable var appState = appState

        return LabeledField(title: "Target Role (optional)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Naming the job you're applying for tailors your summary and cover letter to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Job title you're applying for", text: $appState.jobTarget.title)
                    .textFieldStyle(.roundedInput)
                    .focused($focusedField, equals: .targetTitle)
                TextField("Company", text: $appState.jobTarget.company)
                    .textFieldStyle(.roundedInput)
                    .focused($focusedField, equals: .targetCompany)
                    .id(Field.targetCompany)

                Text("Paste the job posting to get a match score and see which required skills you're missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $appState.jobTarget.descriptionText)
                    .frame(height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                    .focused($focusedField, equals: .jobDescription)
                    .id(Field.jobDescription)
            }
        }
        .id(Field.targetTitle)
    }

    private var skillsSection: some View {
        @Bindable var appState = appState

        return LabeledField(title: "Key Skills") {
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
    }

    private var summarySection: some View {
        @Bindable var appState = appState

        return LabeledField(title: "Professional Summary (optional)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Leave blank and we'll write one from your role, skills and target job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $appState.experience.summary)
                    .frame(height: 90)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.appCardBackground))
                    .focused($focusedField, equals: .summary)
            }
        }
        .id(Field.summary)
    }

    private var experienceSection: some View {
        @Bindable var appState = appState

        return LabeledField(title: "Professional Experience") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach($appState.experience.positions) { $position in
                    positionEditor(position: $position)
                }

                Button {
                    appState.experience.positions.append(WorkExperienceEntry())
                } label: {
                    Label("Add another job", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
    }

    private func positionEditor(position: Binding<WorkExperienceEntry>) -> some View {
        let id = position.wrappedValue.id
        let canDelete = appState.experience.positions.count > 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(position.wrappedValue.trimmedTitle.isEmpty ? "New role" : position.wrappedValue.trimmedTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if canDelete {
                    Button(role: .destructive) {
                        appState.experience.positions.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TextField("Job title", text: position.title)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .positionTitle(id))
            TextField("Company", text: position.company)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .positionCompany(id))
                .id(Field.positionCompany(id))
            TextField("Location (e.g. San Jose, CA)", text: position.location)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .positionLocation(id))
                .id(Field.positionLocation(id))

            HStack(spacing: 10) {
                TextField("Start (e.g. Feb 2017)", text: position.startDate)
                    .textFieldStyle(.roundedInput)
                    .focused($focusedField, equals: .positionStart(id))
                    .id(Field.positionStart(id))
                if !position.wrappedValue.isCurrent {
                    TextField("End", text: position.endDate)
                        .textFieldStyle(.roundedInput)
                        .focused($focusedField, equals: .positionEnd(id))
                        .id(Field.positionEnd(id))
                }
            }

            Toggle("I currently work here", isOn: position.isCurrent)
                .font(.caption)
                .tint(.indigo)

            Text("What you achieved here")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(position.wrappedValue.bullets.indices, id: \.self) { bulletIndex in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    TextField("e.g. Cut unplanned downtime by 30%", text: position.bullets[bulletIndex], axis: .vertical)
                        .textFieldStyle(.roundedInput)
                        .focused($focusedField, equals: .positionBullet(id, bulletIndex))
                        .id(Field.positionBullet(id, bulletIndex))
                    if position.wrappedValue.bullets.count > 1 {
                        Button(role: .destructive) {
                            position.wrappedValue.bullets.remove(at: bulletIndex)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button {
                position.wrappedValue.bullets.append("")
            } label: {
                Label("Add bullet", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(.indigo)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
        .id(Field.positionTitle(id))
    }

    private var educationSection: some View {
        @Bindable var appState = appState

        return LabeledField(title: "Education") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach($appState.experience.educationEntries) { $entry in
                    educationEditor(entry: $entry)
                }

                Button {
                    appState.experience.educationEntries.append(EducationEntry())
                } label: {
                    Label("Add another school", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
    }

    private func educationEditor(entry: Binding<EducationEntry>) -> some View {
        let id = entry.wrappedValue.id
        let canDelete = appState.experience.educationEntries.count > 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.wrappedValue.trimmedDegree.isEmpty ? "New qualification" : entry.wrappedValue.trimmedDegree)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if canDelete {
                    Button(role: .destructive) {
                        appState.experience.educationEntries.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TextField("Degree (e.g. BSc Mechanical Engineering)", text: entry.degree)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .educationDegree(id))
            TextField("School", text: entry.school)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .educationSchool(id))
                .id(Field.educationSchool(id))
            TextField("Location (e.g. San Jose, CA)", text: entry.location)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .educationLocation(id))
                .id(Field.educationLocation(id))
            TextField("Graduation date (e.g. May 2013)", text: entry.graduationDate)
                .textFieldStyle(.roundedInput)
                .focused($focusedField, equals: .educationDate(id))
                .id(Field.educationDate(id))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
        .id(Field.educationDegree(id))
    }

    // MARK: - Validation

    /// The identity and contact fields are all required, and the resume needs at least one fully
    /// filled-in job and one qualification — a resume with a blank contact field or no experience
    /// at all isn't something worth generating a kit from. The optional sections (links, target
    /// role, written summary) are deliberately excluded.
    private var isFormValid: Bool { missingRequirement == nil }

    private var validationMessage: String {
        missingRequirement ?? ""
    }

    private var missingRequirement: String? {
        let experience = appState.experience
        func isBlank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if isBlank(experience.fullName) || isBlank(experience.currentRole)
            || isBlank(experience.email) || isBlank(experience.phone) || isBlank(experience.location) {
            return "Fill in your name, role and contact details to continue."
        }
        if experience.skills.isEmpty {
            return "Add at least one skill to continue."
        }
        if experience.completedPositions.isEmpty {
            return "Add at least one job with a title, company and one achievement bullet."
        }
        if experience.completedEducation.isEmpty {
            return "Add at least one qualification with a degree and school."
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        InputExperienceView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
