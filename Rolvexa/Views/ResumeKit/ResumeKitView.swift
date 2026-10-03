import SwiftUI

struct ResumeKitView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    private enum Tab: String, CaseIterable { case resume = "Resume", coverLetter = "Cover Letter", insights = "Insights" }
    @State private var tab: Tab = .resume

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
            style: appState.selectedResumeTemplateStyle
        )
        .buttonStyle(.bordered)
        .tint(.indigo)
    }

    private func jobFitCard(_ kit: ApplicationKit) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.indigo.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(kit.jobFitScore) / 100)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(kit.jobFitScore)%").font(.title3.bold())
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text("JOB FIT SCORE").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Strong match").font(.subheadline.bold())
                Text("\(kit.suggestions.count) quick improvements suggested")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.indigo.opacity(0.06)))
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
        appState.experience.fullName.isEmpty ? "Jamie Chen" : appState.experience.fullName
    }

    private var displayRole: String {
        appState.experience.currentRole.isEmpty ? "Product Designer" : appState.experience.currentRole
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
        appState.experience.skills.isEmpty ? "product design, user research, and prototyping" : appState.experience.skills.joined(separator: ", ")
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
                education: appState.extractedEducation,
                style: appState.selectedResumeTemplateStyle
            )
        } else {
            ResumeTemplateCard(
                name: displayName,
                role: displayRole,
                summary: appState.aiGeneratedSummary ?? "\(displayRole) with \(appState.experience.yearsOfExperience) of experience, skilled in \(displaySkills). Seeking to bring this expertise to \(displayRoleAtCompany).",
                skills: appState.experience.skills.isEmpty ? ["Product Design", "Figma", "User Research"] : appState.experience.skills,
                yearsOfExperience: appState.experience.yearsOfExperience,
                experienceBullets: experienceBullets,
                email: appState.experience.email.isEmpty ? nil : appState.experience.email,
                phone: appState.experience.phone.isEmpty ? nil : appState.experience.phone,
                location: appState.experience.location.isEmpty ? nil : appState.experience.location,
                education: appState.experience.education.isEmpty ? nil : appState.experience.education,
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

    private var experienceBullets: [String] {
        let summary = appState.experience.workHistorySummary
        let lines = summary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty { return lines }
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

                Text("\(appState.experience.workHistorySummary.isEmpty ? "My background has prepared me to take on new challenges" : appState.experience.workHistorySummary) and I'd welcome the chance to discuss how I can contribute to \(displayCompany)'s continued success.")
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

#Preview {
    let state = AppState()
    state.applicationKit = ApplicationKit(jobFitScore: 87, suggestions: [])
    return NavigationStack {
        ResumeKitView()
    }
    .environment(AppRouter())
    .environment(state)
}
