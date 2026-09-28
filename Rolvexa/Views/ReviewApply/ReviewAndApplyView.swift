import SwiftUI
import UniformTypeIdentifiers

struct ReviewAndApplyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var fixErrorMessage: String?
    @State private var fixProgress: Double = 0

    var body: some View {
        ZStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to send").font(.title2.bold())
                    Text("Double-check your kit before applying to \(appState.jobTarget.company.isEmpty ? "this role" : appState.jobTarget.company)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                jobSummaryCard

                if !appState.suggestedJobTitles.isEmpty {
                    jobFitTitlesCard
                }

                if let kit = appState.applicationKit, kit.jobFitScore < 100, !kit.suggestions.isEmpty {
                    improveScoreCard(kit)
                }

                Text("YOUR KIT").font(.caption.bold()).foregroundStyle(.secondary)
                kitRow(
                    icon: "doc.text.fill",
                    title: "Resume",
                    subtitle: "Tailored & ready",
                    baseFilename: "Resume",
                    documentTitle: "Resume",
                    exportText: appState.resumeExportText,
                    originalFileData: keepsOriginalResumeLayout ? appState.uploadedResumeFileData : nil,
                    originalFileExtension: keepsOriginalResumeLayout ? appState.uploadedResumeFileExtension : nil,
                    // Same reasoning as ResumeKitView's download button: when keeping the
                    // original layout, only ever offer the original's own format (guaranteed
                    // byte-for-byte identical design) — never a regenerated cross-format dump
                    // that silently discards it. Otherwise offer both, now that PDFDocumentRenderer
                    // applies the chosen template's styling too, not just Word.
                    format: keepsOriginalResumeLayout ? resumeOriginalFormat : nil
                )
                kitRow(icon: "envelope.fill", title: "Cover Letter", subtitle: "Tailored & ready", baseFilename: "CoverLetter", documentTitle: "Cover Letter", exportText: appState.coverLetterExportText, format: nil)
                kitRow(icon: "chart.bar.fill", title: "Job Fit Analysis", subtitle: "\(appState.applicationKit?.jobFitScore ?? 0)% match", baseFilename: "JobFitAnalysis", documentTitle: "Job Fit Analysis", exportText: appState.jobFitExportText, format: nil)

                Button {
                    submit()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(isSubmitting ? "Submitting…" : "Submit Application")
                    }
                }
                .buttonStyle(.primaryGradient)
                .disabled(isSubmitting)

                Text("You can edit your kit anytime from your dashboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }

        if appState.isImprovingResume {
            FixingResumeOverlay(progress: fixProgress)
        }
        }
        .navigationTitle("Review & Send")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        #endif
        .toolbar {
            // Reaching this screen via the uploaded-resume path builds up a deep, mixed-type
            // navigation stack (Upload → Review → Templates → AI Building → Kit → here). The
            // system-provided back button relies on NavigationPath's own bookkeeping, which can
            // misbehave with long heterogeneous stacks; an explicit single `path.removeLast()`
            // guarantees "back" always means exactly one screen, no matter how deep the stack is.
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    router.pop()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .appTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Application submitted", isPresented: $didSubmit) {
            Button("Done") { router.popToRoot() }
        }
        .alert("Couldn't fix resume", isPresented: Binding(
            get: { fixErrorMessage != nil },
            set: { if !$0 { fixErrorMessage = nil } }
        )) {
            Button("OK") { fixErrorMessage = nil }
        } message: {
            Text(fixErrorMessage ?? "")
        }
    }

    /// Falls back to the resume's own last/current position when no job target title was
    /// entered — a real detail from the resume reads better than a generic placeholder.
    private var jobSummaryTitle: String {
        if !appState.jobTarget.title.isEmpty { return appState.jobTarget.title }
        if !appState.experience.currentRole.isEmpty { return appState.experience.currentRole }
        return "Untitled Role"
    }

    private var jobSummaryCompany: String {
        if !appState.jobTarget.company.isEmpty { return appState.jobTarget.company }
        if let company = appState.extractedCompany, !company.isEmpty { return company }
        return "Unknown Company"
    }

    private var jobSummaryCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.12)).frame(width: 44, height: 44)
                .overlay { Image(systemName: "building.2.fill").foregroundStyle(Color.indigo) }
            VStack(alignment: .leading, spacing: 2) {
                Text(jobSummaryTitle)
                    .font(.subheadline.bold())
                Text(jobSummaryCompany)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    tag("Remote")
                    tag("Full-time")
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    private var jobFitTitlesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(Color.indigo)
                Text("Other roles you're a great fit for")
                    .font(.subheadline.bold())
            }
            FlowLayout(spacing: 8) {
                ForEach(appState.suggestedJobTitles, id: \.self) { title in
                    tag(title)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    /// The text "Fix It For Me" would actually operate on for the current build source — same
    /// source ``fixResume`` reads from, so the auto-fixability check below matches reality.
    private var currentResumeSourceText: String {
        if appState.buildSource == .upload {
            return appState.extractedResumeText ?? ""
        }
        return appState.experience.workHistorySummary
    }

    private func improveScoreCard(_ kit: ApplicationKit) -> some View {
        // Suggestions like "Add quantifiable metrics" or "Add missing sections" require inventing
        // content this offline, rule-based engine deliberately never adds — offering a button that
        // can only fail for those leaves the user stuck in a "Couldn't fix resume" loop with no
        // way forward, so show manual guidance instead once nothing is left to safely auto-fix.
        let canAutoFix = ResumeAnalysisEngine.hasAutoFixableIssues(
            in: currentResumeSourceText,
            suggestionTitles: kit.suggestions.map(\.title)
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .foregroundStyle(Color.indigo)
                Text("Reach a 100% score")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(kit.jobFitScore)% now")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(kit.suggestions) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Color.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.footnote.bold())
                        if !suggestion.detail.isEmpty {
                            Text(suggestion.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if canAutoFix {
                if appState.keepOriginalUploadedLayout {
                    Text("Using this replaces your kept original file with a regenerated version for downloads — your original design won't be available anymore.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await fixResume(kit) }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Fix It For Me")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.primaryGradient)
                .disabled(appState.isImprovingResume)
            } else {
                Text("These need your input — add the details above yourself, since we can't invent achievements or metrics for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    private func fixResume(_ kit: ApplicationKit) async {
        guard !appState.isImprovingResume else { return }

        appState.isImprovingResume = true
        fixProgress = 0
        // A simple animated approximation — the actual fix duration varies (longer if the
        // bundled on-device model is available and engages), so this eases toward 90% and only
        // jumps to 100% once the real work below has actually finished.
        let progressTask = Task {
            while !Task.isCancelled, fixProgress < 0.9 {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation { fixProgress = min(fixProgress + 0.08, 0.9) }
            }
        }
        defer {
            progressTask.cancel()
            appState.isImprovingResume = false
        }

        let issues = kit.suggestions.map {
            ResumeAnalysisEngine.GrammarSuggestionItem(title: $0.title, detail: $0.detail)
        }

        do {
            if appState.buildSource == .upload, let resumeText = appState.extractedResumeText, !resumeText.isEmpty {
                let improved = try await ResumeAnalysisEngine.improveResume(resumeText: resumeText, suggestions: issues, currentScore: kit.jobFitScore)
                appState.extractedResumeText = improved.improvedText
                appState.extractedResumeDisplayText = improved.improvedText
                appState.resumeTextWasManuallyFixed = true
                appState.applicationKit = ApplicationKit(
                    jobFitScore: improved.qualityScore,
                    suggestions: improved.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) }
                )
            } else {
                // For "write from scratch", the only free-form prose field is the work history
                // summary — name/role/skills are structured, not something to "rewrite". Improve
                // that field, then re-score the fully assembled resume text. Gating on a rescore
                // of the fragment alone (as `improveResume` does) would compare a bare paragraph's
                // score — no Summary/Skills headers, so always heavily penalized — against the
                // full resume's score, guaranteeing rejection regardless of how good the rewrite
                // actually is. So gate on a rescore of the *full* document instead.
                let workHistory = appState.experience.workHistorySummary
                guard !workHistory.isEmpty else {
                    fixErrorMessage = "Add a work history summary first so there's something to improve."
                    return
                }
                let improvedWorkHistory = try await ResumeAnalysisEngine.applyFixes(to: workHistory)
                appState.experience.workHistorySummary = improvedWorkHistory
                let rescored = try await ResumeAnalysisEngine.reviewGrammar(resumeText: appState.resumeExportText())
                guard rescored.qualityScore >= kit.jobFitScore else {
                    appState.experience.workHistorySummary = workHistory
                    print("[ResumeAnalysisEngine] fixResume: full-document rescore \(rescored.qualityScore) worse than \(kit.jobFitScore) — discarding")
                    throw ResumeAnalysisError.noImprovement
                }
                appState.applicationKit = ApplicationKit(
                    jobFitScore: rescored.qualityScore,
                    suggestions: rescored.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) }
                )
            }
            appState.aiReviewedThisSession = true
        } catch ResumeAnalysisError.noImprovement {
            print("[ResumeAnalysisEngine] improveResume: nothing safe to fix, or the fix didn't score higher")
            fixErrorMessage = "We couldn't find anything more to safely fix automatically. Try tightening a sentence or adding a metric yourself."
        } catch {
            print("[ResumeAnalysisEngine] improveResume failed: \(error)")
            fixErrorMessage = "Something went wrong while improving your resume. Please try again."
        }
        withAnimation { fixProgress = 1.0 }
        try? await Task.sleep(for: .milliseconds(250))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.appSubtleFill))
    }

    private var keepsOriginalResumeLayout: Bool {
        appState.buildSource == .upload && appState.keepOriginalUploadedLayout
            && appState.uploadedResumeFileData != nil && !appState.resumeTextWasManuallyFixed
    }

    /// The original uploaded file's own format — the only format that can ever be byte-for-byte
    /// identical to its actual design, so this is what "keep original layout" downloads lock to.
    private var resumeOriginalFormat: ExportFormat? {
        appState.uploadedResumeFileExtension.map { $0 == "pdf" ? .pdf : .word }
    }

    private func kitRow(
        icon: String,
        title: String,
        subtitle: String,
        baseFilename: String,
        documentTitle: String,
        exportText: @escaping () -> String,
        originalFileData: Data? = nil,
        originalFileExtension: String? = nil,
        format: ExportFormat? = .word
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.12)).frame(width: 40, height: 40)
                .overlay { Image(systemName: icon).foregroundStyle(Color.indigo) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundStyle(.green)
            }
            Spacer()
            DownloadMenuButton(
                documentTitle: documentTitle,
                baseFilename: baseFilename,
                textProvider: exportText,
                originalFileData: originalFileData,
                originalFileExtension: originalFileExtension,
                fixedFormat: format,
                style: appState.selectedResumeTemplateStyle
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

    private func submit() {
        isSubmitting = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isSubmitting = false
            didSubmit = true
        }
    }
}

#Preview {
    NavigationStack {
        ReviewAndApplyView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
