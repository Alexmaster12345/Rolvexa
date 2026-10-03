import SwiftUI
import UniformTypeIdentifiers

struct ReviewAndApplyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var didFinish = false
    @State private var fixErrorMessage: String?
    @State private var fixSuccessMessage: String?
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

                if let kit = appState.applicationKit, kit.resumeScore < 100, !kit.suggestions.isEmpty {
                    improveScoreCard(kit)
                }

                Text("YOUR KIT").font(.caption.bold()).foregroundStyle(.secondary)
                kitRow(
                    icon: "doc.text.fill",
                    title: "Resume",
                    subtitle: kitSubtitle,
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
                    format: keepsOriginalResumeLayout ? resumeOriginalFormat : nil,
                    includesPhoto: true
                )
                kitRow(icon: "envelope.fill", title: "Cover Letter", subtitle: kitSubtitle, baseFilename: "CoverLetter", documentTitle: "Cover Letter", exportText: appState.coverLetterExportText, format: nil)
                jobFitKitRow

                // Was "Submit Application", which slept for a second and then announced
                // "Application submitted". Nothing was sent — the app has no networking at all,
                // by design — so a user could tap it, believe they had applied, and never
                // actually apply. The button now says what it does: the kit is finished, and
                // sending it is a step the user takes themselves.
                Button {
                    didFinish = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("I'm done — my kit is ready")
                    }
                }
                .buttonStyle(.primaryGradient)

                Text("Download each document above, then send them from your email or the employer's site. Rolvexa never uploads anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .appTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close and start over")
            }
        }
        .alert("Your kit is ready", isPresented: $didFinish) {
            Button("Done") { router.popToRoot() }
        } message: {
            Text("Rolvexa doesn't send applications — download your resume and cover letter, then submit them yourself.")
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

    /// "Tailored" is only true when a target role was given — otherwise the kit is simply
    /// built from what was entered, and saying otherwise overstates what the app did.
    private var kitSubtitle: String {
        appState.jobTarget.title.isEmpty ? "Ready to download" : "Tailored & ready"
    }

    /// The row only promises a "job fit analysis" when a job description was actually supplied;
    /// otherwise it's a resume report, and says so.
    ///
    /// `jobFitAnalysis` recomputes on every read (~1.3 ms — it rebuilds the export text and
    /// re-runs the match), and SwiftUI may evaluate a body several times per interaction. Read
    /// once here rather than from separate title and subtitle properties, which doubled the work
    /// for a single row.
    private var jobFitKitRow: some View {
        let fit = appState.jobFitAnalysis
        let title = fit == nil ? "Resume Report" : "Job Fit Analysis"
        let subtitle = fit.map { "\($0.overallScore)% match — \($0.summaryLabel.lowercased())" }
            ?? "\(appState.applicationKit?.resumeScore ?? 0)% resume score"

        return kitRow(
            icon: "chart.bar.fill",
            title: title,
            subtitle: subtitle,
            baseFilename: "JobFitAnalysis",
            documentTitle: title,
            exportText: appState.jobFitExportText,
            format: nil
        )
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
                // No "Remote"/"Full-time" chips here: the app never asks for the work
                // arrangement or employment type, so those were decoration asserting facts
                // about a job it knows nothing about. The level is shown only when a posting
                // was actually supplied.
                if appState.jobFitAnalysis != nil {
                    HStack(spacing: 6) {
                        tag("Matched to your posting")
                    }
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
                Text("\(kit.resumeScore)% now")
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

            // A fix can genuinely rewrite the text without moving the coarse heuristic score (the
            // score only counts things like missing metrics or weak-opener phrases, so tighter
            // wording at the same structure scores identically). Without this, the user taps the
            // button, waits through the overlay, and nothing whatsoever appears to change —
            // indistinguishable from a silent no-op.
            if let fixSuccessMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(fixSuccessMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if canAutoFix {
                if appState.isKeepingOriginalUploadedLayout {
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
        fixSuccessMessage = nil
        // A simple animated approximation — the actual fix duration varies (longer when Apple
        // Intelligence is available and engages), so this eases toward 90% and only jumps to
        // 100% once the real work below has actually finished.
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

        // Deferred until after the minimum-display-duration sleep below: `fixErrorMessage`
        // drives a native `.alert`, which renders above every custom view including
        // `FixingResumeOverlay` — setting it immediately (the instant a fix fails) would bury
        // the overlay under the alert before it's had any chance to actually be seen, especially
        // when the fix resolves in only a few milliseconds.
        var pendingErrorMessage: String?
        var pendingSuccessMessage: String?

        /// Built once the new score is known. Phrased differently when the score didn't move,
        /// because "we rewrote your text but the number is identical" is otherwise indistinguishable
        /// from "nothing happened" — the score only rewards structural things (metrics, sections,
        /// bullets), so tighter wording at the same structure legitimately scores the same.
        func successMessage(newScore: Int) -> String {
            newScore > kit.resumeScore
                ? "Your wording was tightened and your score went from \(kit.resumeScore)% to \(newScore)%."
                : "Your wording was tightened. The score stayed at \(newScore)% — what's left needs detail only you can add."
        }

        do {
            if appState.buildSource == .upload, let resumeText = appState.extractedResumeText, !resumeText.isEmpty {
                let improved = try await ResumeAnalysisEngine.improveResume(resumeText: resumeText, suggestions: issues, currentScore: kit.resumeScore)
                appState.updateExtractedResumeText(improved.improvedText)
                appState.resumeTextWasManuallyFixed = true
                appState.applicationKit = ApplicationKit(
                    resumeScore: improved.qualityScore,
                    suggestions: improved.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) }
                )
                appState.recordResumeScore(improved.qualityScore)
                pendingSuccessMessage = successMessage(newScore: improved.qualityScore)
            } else {
                // For "write from scratch", the only free-form prose field is the work history
                // summary — name/role/skills are structured, not something to "rewrite". Improve
                // that field, then re-score the fully assembled resume text. Gating on a rescore
                // of the fragment alone (as `improveResume` does) would compare a bare paragraph's
                // score — no Summary/Skills headers, so always heavily penalized — against the
                // full resume's score, guaranteeing rejection regardless of how good the rewrite
                // actually is. So gate on a rescore of the *full* document instead.
                let originalPositions = appState.experience.positions
                guard !appState.experience.workHistorySummary.isEmpty else {
                    pendingErrorMessage = "Add a job with at least one achievement bullet first so there's something to improve."
                    withAnimation { fixProgress = 1.0 }
                    try? await Task.sleep(for: .milliseconds(700))
                    fixErrorMessage = pendingErrorMessage
                    return
                }
                // Rewrite each achievement bullet in place. The bullets *are* the free-form prose
                // now that jobs are structured — rewriting a flattened paragraph and assigning it
                // back would collapse every job into one blob.
                var rewritten = originalPositions
                for positionIndex in rewritten.indices {
                    for bulletIndex in rewritten[positionIndex].bullets.indices {
                        let bullet = rewritten[positionIndex].bullets[bulletIndex]
                            .trimmingCharacters(in: .whitespaces)
                        guard !bullet.isEmpty else { continue }
                        rewritten[positionIndex].bullets[bulletIndex] =
                            try await ResumeAnalysisEngine.applyFixes(to: bullet)
                    }
                }
                appState.experience.positions = rewritten
                let rescored = try await ResumeAnalysisEngine.reviewGrammar(resumeText: appState.resumeExportText())
                guard rescored.qualityScore >= kit.resumeScore else {
                    appState.experience.positions = originalPositions
                    print("[ResumeAnalysisEngine] fixResume: full-document rescore \(rescored.qualityScore) worse than \(kit.resumeScore) — discarding")
                    throw ResumeAnalysisError.noImprovement
                }
                appState.applicationKit = ApplicationKit(
                    resumeScore: rescored.qualityScore,
                    suggestions: rescored.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) }
                )
                appState.recordResumeScore(rescored.qualityScore)
                pendingSuccessMessage = successMessage(newScore: rescored.qualityScore)
            }
            appState.aiReviewedThisSession = true
        } catch ResumeAnalysisError.noImprovement {
            print("[ResumeAnalysisEngine] improveResume: nothing safe to fix, or the fix didn't score higher")
            pendingErrorMessage = "We couldn't find anything more to safely fix automatically. Try tightening a sentence or adding a metric yourself."
        } catch {
            print("[ResumeAnalysisEngine] improveResume failed: \(error)")
            pendingErrorMessage = "Something went wrong while improving your resume. Please try again."
        }
        withAnimation { fixProgress = 1.0 }
        // A fix that resolves (success or failure) in a handful of milliseconds — e.g. when the
        // on-device model isn't engaged — could otherwise dismiss the overlay before SwiftUI
        // ever renders a visible frame of it. This guarantees it's actually seen.
        try? await Task.sleep(for: .milliseconds(700))
        fixErrorMessage = pendingErrorMessage
        fixSuccessMessage = pendingSuccessMessage
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.appSubtleFill))
    }

    private var keepsOriginalResumeLayout: Bool {
        appState.isKeepingOriginalUploadedLayout
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
        format: ExportFormat? = .word,
        includesPhoto: Bool = false
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
                style: appState.selectedResumeTemplateStyle,
                photoData: includesPhoto ? appState.experience.photoData : nil
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
    }

}

#Preview {
    NavigationStack {
        ReviewAndApplyView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
