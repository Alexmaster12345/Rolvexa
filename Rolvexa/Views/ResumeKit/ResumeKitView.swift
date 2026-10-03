import SwiftUI

struct ResumeKitView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    private enum Tab: String, CaseIterable { case resume = "Resume", coverLetter = "Cover Letter", insights = "Insights" }
    @State private var tab: Tab = .resume
    @State private var isEditingJobDescription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepProgressHeader(step: 4, totalSteps: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Application Kit is ready!")
                        .font(.title2.bold())
                    if !appState.jobTarget.title.isEmpty {
                        Text("Tailored for \(appState.jobTarget.title) at \(appState.jobTarget.company)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if appState.aiReviewedThisSession {
                        Label("Personalized with on-device AI", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(Color.indigo)
                    }
                }

                if let kit = appState.applicationKit {
                    jobFitCard(kit)
                }

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                tabContent

                if let kit = appState.applicationKit {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI SUGGESTIONS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ForEach(kit.suggestions) { suggestion in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                                Text(suggestion.title).font(.subheadline)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.1)))
                        }
                    }
                }

                if tab != .insights {
                    downloadButton
                }

                HStack(spacing: 12) {
                    Button("Edit") { router.pop() }
                        .buttonStyle(.bordered)
                        .tint(.indigo)

                    Button {
                        router.push(.reviewAndApply)
                    } label: {
                        HStack { Text("Continue"); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(.primaryGradient)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $isEditingJobDescription) {
            JobDescriptionSheet()
        }
    }

    private var downloadButton: some View {
        let isResumeTab = tab == .resume
        let documentTitle = isResumeTab ? "Resume" : "Cover Letter"
        let baseFilename = isResumeTab ? "Resume" : "CoverLetter"
        let textProvider: () -> String = {
            isResumeTab ? appState.resumeExportText() : appState.coverLetterExportText()
        }
        let buttonLabel = AnyView(
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("Download \(documentTitle)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        )

        let keepsOriginal = isResumeTab && appState.isKeepingOriginalUploadedLayout
        let originalData = keepsOriginal ? appState.uploadedResumeFileData : nil
        let originalExtension = keepsOriginal ? appState.uploadedResumeFileExtension : nil
        // When "keep original layout" is on, a regenerated file in the *other* format can never
        // actually be the original's design — offering that choice silently swaps out the real
        // design for a plain re-flowed dump the moment someone taps the "wrong" format. Locking
        // the button to the original's own format guarantees every download is byte-for-byte
        // identical to what was uploaded. Once there's no original to preserve (a template was
        // picked, or this is a from-scratch resume), both PDF and Word are offered — the
        // template's accent color now renders correctly in both (see PDFDocumentRenderer).
        let originalFormat: ExportFormat? = originalExtension.map { $0 == "pdf" ? .pdf : .word }
        let fixedFormat: ExportFormat? = originalData != nil ? originalFormat : nil

        return DownloadMenuButton(
            documentTitle: documentTitle,
            baseFilename: baseFilename,
            textProvider: textProvider,
            label: buttonLabel,
            originalFileData: originalData,
            originalFileExtension: originalExtension,
            fixedFormat: fixedFormat,
            style: appState.selectedResumeTemplateStyle,
            // A cover letter has no sidebar to hold a headshot, so only the resume gets one.
            photoData: isResumeTab ? appState.experience.photoData : nil
        )
        .buttonStyle(.bordered)
        .tint(.indigo)
    }

    /// Shows a real job-fit breakdown when a job description has been pasted, and the resume's
    /// own quality score — under its own name — when it hasn't.
    ///
    /// This card used to print "JOB FIT SCORE / Strong match" over the resume quality score, so
    /// it reported a match against a job the app had never seen.
    private func jobFitCard(_ kit: ApplicationKit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fit = appState.jobFitAnalysis {
                scoreHeader(
                    percent: fit.overallScore,
                    caption: "JOB FIT",
                    headline: fit.summaryLabel,
                    detail: "Measured against the job description you pasted"
                )

                VStack(spacing: 6) {
                    ForEach(fit.components) { component in
                        HStack {
                            Text(component.title).font(.caption.bold())
                            Spacer()
                            Text(component.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            Text("\(component.percent)%")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(Color.indigo)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                if !fit.missingSkills.isEmpty {
                    skillChips(title: "Missing", items: fit.missingSkills, tint: .red)
                }
                if !fit.matchedSkills.isEmpty {
                    skillChips(title: "Matched", items: fit.matchedSkills, tint: .green)
                }

                Button("Edit job description") { isEditingJobDescription = true }
                    .font(.caption.bold())
                    .buttonStyle(.borderless)
                    .tint(.indigo)
            } else {
                scoreHeader(
                    percent: kit.resumeScore,
                    caption: "RESUME SCORE",
                    headline: kit.suggestions.count == 1
                        ? "1 quick improvement suggested"
                        : "\(kit.suggestions.count) quick improvements suggested",
                    detail: "How well-written your resume is — not a match against any job yet"
                )

                Button {
                    isEditingJobDescription = true
                } label: {
                    Label("Add job description to see your match", systemImage: "text.badge.plus")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.indigo.opacity(0.06)))
    }

    private func scoreHeader(percent: Int, caption: String, headline: String, detail: String) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.indigo.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(percent) / 100)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.title3.bold())
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.caption.bold()).foregroundStyle(.secondary)
                Text(headline).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        // Spoken as one sentence. Left as separate elements VoiceOver read the ring, the
        // caption, the headline and the detail as four disconnected fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(percent) percent")
        .accessibilityValue("\(headline). \(detail)")
    }

    private func skillChips(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items.prefix(12), id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .foregroundStyle(tint)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .resume:
            resumeContent
        case .coverLetter:
            coverLetterContent
        case .insights:
            insightsPreview
        }
    }

    private var displayName: String {
        appState.experience.fullName.isEmpty ? "Your Name" : appState.experience.fullName
    }

    private var displayRole: String {
        appState.experience.currentRole.isEmpty ? "Your Role" : appState.experience.currentRole
    }

    private var displayCompany: String {
        appState.jobTarget.company.isEmpty ? "your company" : appState.jobTarget.company
    }

    /// "this role" already reads as a full phrase on its own — appending the literal word
    /// "role" after it (as the real-title case needs) would read "this role role".
    private var displayRoleAtCompany: String {
        appState.jobTarget.title.isEmpty
            ? "this role at \(displayCompany)"
            : "the \(appState.jobTarget.title) role at \(displayCompany)"
    }

    private var displaySkills: String {
        appState.experience.skills.isEmpty ? "your key skills" : appState.experience.skills.joined(separator: ", ")
    }

    /// Mirrors `coverLetterExportText()` so the on-screen cover letter and the downloaded one
    /// read identically.
    private var coverLetterHighlightSentence: String {
        let highlights = appState.experience.coverLetterHighlights
        return highlights.isEmpty
            ? "My background has prepared me to take on new challenges."
            : "Recent highlights: \(highlights)."
    }

    /// Same precedence the export uses — what the user wrote, else the AI pass, else the
    /// generated sentence — so the preview and the downloaded file can't show different
    /// "About me" text.
    private var displaySummary: String {
        let written = appState.experience.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !written.isEmpty { return written }
        if let generated = appState.aiGeneratedSummary { return generated }
        return "\(displayRole) with \(appState.experience.yearsOfExperience) of experience, skilled in \(displaySkills). Seeking to bring this expertise to \(displayRoleAtCompany)."
    }

    private func cleanedExtractedText(_ raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty == true {
                continue
            }
            result.append(line)
        }
        while result.first?.isEmpty == true { result.removeFirst() }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    @ViewBuilder
    private var resumeContent: some View {
        // These first three branches are all upload-specific (original file passthrough, kept
        // original layout, or extracted upload text). Gating them on `buildSource == .upload`
        // stops leftover state from an earlier upload-flow test in the same app session (there's
        // no AppState reset between flows) from making a later "write from scratch" session
        // render as if it were an upload — which showed up as a plain, unstyled resume no matter
        // which template was picked, since that stale state bypassed ResumeTemplateCard entirely.
        if appState.buildSource == .upload,
           appState.isKeepingOriginalUploadedLayout,
           let data = appState.uploadedResumeFileData,
           appState.uploadedResumeFileExtension == "pdf" {
            // The real original PDF, rendered with its actual layout — text extraction alone
            // can't reproduce columns, fonts, or images, so this is the only faithful option.
            PDFKitView(data: data)
                .frame(height: 480)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.appPageBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.appSeparator.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        } else if appState.buildSource == .upload,
                  let extracted = appState.extractedResumeText, !extracted.isEmpty, appState.isKeepingOriginalUploadedLayout {
            // Fallback for formats we can't render visually in-app (e.g. .docx) — at least show
            // the extracted text rather than forcing the styled template on someone who opted out.
            plainOriginalResumeCard(extracted)
        } else if appState.buildSource == .upload,
                  let extracted = appState.extractedResumeText, !extracted.isEmpty {
            ResumeTemplateCard(
                name: appState.experience.fullName.isEmpty ? (appState.uploadedFileName ?? "Your Resume") : appState.experience.fullName,
                role: appState.experience.currentRole,
                summary: appState.extractedSummary ?? "",
                skills: appState.experience.skills,
                yearsOfExperience: "",
                experienceBullets: [],
                rawText: cleanedExtractedText(appState.extractedResumeDisplayText ?? extracted),
                email: appState.extractedEmail,
                phone: appState.extractedPhone,
                location: appState.extractedLocation,
                links: appState.extractedLinks,
                education: appState.extractedEducation,
                style: appState.selectedResumeTemplateStyle
            )
        } else {
            ResumeTemplateCard(
                name: displayName,
                role: displayRole,
                summary: displaySummary,
                skills: appState.experience.skills.isEmpty ? ["Your first skill", "Your second skill"] : appState.experience.skills,
                yearsOfExperience: appState.experience.yearsOfExperience,
                experienceBullets: experienceBullets,
                email: appState.experience.email.isEmpty ? nil : appState.experience.email,
                phone: appState.experience.phone.isEmpty ? nil : appState.experience.phone,
                location: appState.experience.location.isEmpty ? nil : appState.experience.location,
                links: appState.experience.links,
                education: appState.experience.educationSummary.isEmpty ? nil : appState.experience.educationSummary,
                positions: appState.experience.completedPositions,
                photoData: appState.experience.photoData,
                style: appState.selectedResumeTemplateStyle
            )
        }
    }

    /// When the user chose "Use Uploaded File" (keep original layout) on the Templates screen,
    /// this shows their resume without any of the app's own styling — no indigo sidebar, no
    /// restructured sections — since applying template chrome would defeat the point of that
    /// choice. Uses the untouched original text, not the display copy that has the header
    /// block stripped for the templated view.
    private func plainOriginalResumeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.indigo)
                Text(appState.uploadedFileName ?? "Uploaded Resume")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            Divider()

            Text(cleanedExtractedText(text))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.appPageBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appSeparator.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    /// Only used as the fallback when there are no structured positions yet — with entries
    /// filled in, the card renders each job from `positions` instead.
    private var experienceBullets: [String] {
        let bullets = appState.experience.positions.flatMap(\.filledBullets)
        if !bullets.isEmpty { return bullets }
        return ["Add your work history to see it tailored here."]
    }

    private var coverLetterContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dear Hiring Manager,").font(.subheadline.bold())

            if let aiBody = appState.aiGeneratedCoverLetterBody {
                Text(aiBody).font(.footnote)
            } else {
                Text("I'm excited to apply for \(displayRoleAtCompany). As a \(displayRole) with \(appState.experience.yearsOfExperience) of experience in \(displaySkills), I'm confident I can make an immediate impact on your team.")
                    .font(.footnote)

                Text("\(coverLetterHighlightSentence) I'd welcome the chance to discuss how I can contribute to \(displayCompany)'s continued success.")
                    .font(.footnote)
            }

            Text("Sincerely,").font(.footnote)
            Text(displayName).font(.footnote.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    private var insightsPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            insightRow(title: "Keyword Match", percent: 84)
            insightRow(title: "Experience Alignment", percent: 91)
            insightRow(title: "Skills Coverage", percent: 76)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    private func insightRow(title: String, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(percent)%").font(.subheadline.bold())
            }
            ProgressView(value: Double(percent), total: 100)
                .tint(.indigo)
        }
    }
}

#Preview("Kit — no job description") {
    let state = AppState()
    state.applicationKit = ApplicationKit(resumeScore: 87, suggestions: [
        ImprovementSuggestion(title: "Add quantifiable metrics to your last role", detail: "")
    ])
    return NavigationStack {
        ResumeKitView()
    }
    .environment(AppRouter())
    .environment(state)
}

#Preview("Kit — with job description") {
    let state = AppState()
    state.buildSource = .write
    state.experience.fullName = "Jane Doe"
    state.experience.currentRole = "Senior Infrastructure Engineer"
    state.experience.skills = ["Python", "Linux", "Kubernetes", "Docker", "AWS", "CI/CD"]
    var job = WorkExperienceEntry()
    job.title = "Senior Infrastructure Engineer"
    job.company = "Acme Corporation"
    job.startDate = "2019"
    job.isCurrent = true
    job.bullets = ["Ran containerised services on Kubernetes across three AWS regions",
                   "Automated deployments with CI/CD and Docker, improving platform reliability"]
    state.experience.positions = [job]
    var school = EducationEntry()
    school.degree = "BSc Computer Science"
    school.school = "State University"
    state.experience.educationEntries = [school]
    state.jobTarget.title = "Senior SRE"
    state.jobTarget.company = "Initech"
    state.jobTarget.descriptionText = """
    Senior Site Reliability Engineer — Initech
    You will run services on Kubernetes, manage infrastructure with Terraform, and automate
    deployments through CI/CD pipelines on AWS. Python and Linux required. Docker essential.
    Reliability and compliance are central to this platform. Bachelor degree preferred.
    """
    state.applicationKit = ApplicationKit(resumeScore: 88, suggestions: [])
    return NavigationStack {
        ResumeKitView()
    }
    .environment(AppRouter())
    .environment(state)
}
