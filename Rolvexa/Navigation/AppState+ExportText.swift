import Foundation

extension AppState {
    func resumeExportText() -> String {
        // Gate on buildSource: extractedResumeText can hold a stale value left over from an
        // earlier upload-flow test in the same app session (AppState is never reset between
        // flows) — without this check, a later "write from scratch" export could silently
        // return someone else's previously-uploaded resume text instead of what was written.
        if buildSource == .upload, let extracted = extractedResumeText, !extracted.isEmpty {
            // "Keep original layout" downloads bypass this function entirely (they use the
            // original file's exact bytes) — but on the rare path where this text still gets
            // read for that mode, the truly original raw extraction is the faithful answer.
            if keepOriginalUploadedLayout {
                return extracted
            }
            // Otherwise ("Replace with Template"): PDF/DOCX text extraction order frequently
            // doesn't match visual reading order — for multi-column or sidebar layouts the
            // name/contact/summary block can extract in the *middle* of the document, and
            // section headers can end up with no body directly under them (their real content
            // extracted elsewhere). Returning that raw dump as "the resume" reads as broken, not
            // templated. Rebuild it in the same sane order the in-app preview already uses.
            return structuredUploadExportText(rawExtracted: extracted)
        }
        let name = experience.fullName.isEmpty ? "Jamie Chen" : experience.fullName
        let role = experience.currentRole.isEmpty ? "Product Designer" : experience.currentRole
        let skills = experience.skills.isEmpty ? "product design, user research, and prototyping" : experience.skills.joined(separator: ", ")
        let company = jobTarget.company.isEmpty ? "your company" : jobTarget.company
        // "this role" already reads as a full phrase on its own — appending the literal word
        // "role" after it (as the non-empty-title branch needs) would read "this role role".
        let roleAtCompany = jobTarget.title.isEmpty ? "this role at \(company)" : "the \(jobTarget.title) role at \(company)"
        let summary = aiGeneratedSummary ?? "\(role) with \(experience.yearsOfExperience) of experience, skilled in \(skills). Seeking to bring this expertise to \(roleAtCompany)."
        let contactLine = [experience.email, experience.phone, experience.location]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let educationBlock = experience.education.isEmpty ? "" : "\n\nEDUCATION\n\(experience.education)"
        return """
        \(name)
        \(role)\(contactLine.isEmpty ? "" : "\n\(contactLine)")

        SUMMARY
        \(summary)

        SKILLS
        \(skills)

        EXPERIENCE
        \(experience.workHistorySummary.isEmpty ? "Add your work history to see it tailored here." : experience.workHistorySummary)\(educationBlock)
        """
    }

    /// Reassembles an uploaded resume's extracted text into the same sane order the in-app
    /// preview (`ResumeTemplateCard`) already presents it in: name/role/contact up top, then the
    /// summary, then the rest of the body with dangling section headers (no body under them —
    /// their real content extracted elsewhere) removed.
    private func structuredUploadExportText(rawExtracted: String) -> String {
        let name = experience.fullName.isEmpty ? (uploadedFileName ?? "Your Resume") : experience.fullName
        let role = experience.currentRole
        let contactLine = [extractedEmail, extractedPhone, extractedLocation].compactMap { $0 }.joined(separator: " | ")
        let summary = extractedSummary ?? ""

        // `extractedResumeDisplayText` is SUPPOSED to already have the header block (name/role/
        // contact/summary) stripped out from wherever it landed in the raw extraction — but that
        // stripping only fires when a "phone | email | location"-style contact line was
        // successfully detected upstream, which isn't guaranteed for every resume's exact
        // formatting. Rather than trust that silently, filter the body by content directly, so
        // the block this function is about to print up top can never also survive somewhere
        // in the middle of the body — regardless of whether the upstream detection worked.
        let linesToExclude: Set<String> = Set(
            ([name, role, summary] + [extractedEmail, extractedPhone, extractedLocation].compactMap { $0 })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // A single first-name match on a short, sentence-free line is a strong signal of a
        // duplicate name occurrence (some multi-column/sidebar resume layouts render the
        // candidate's name a second time — e.g. a small profile card — which PDF text
        // extraction reproduces as a completely separate line elsewhere, sometimes with a
        // slightly different OCR-like rendering of the surname). An exact-string match against
        // `name` alone can't catch that, since the text genuinely differs.
        let nameFirstWord = name.split(separator: " ").first.map(String.init) ?? ""

        func looksLikeDuplicateNameLine(_ trimmed: String) -> Bool {
            guard !nameFirstWord.isEmpty, trimmed.hasPrefix(nameFirstWord) else { return false }
            let words = trimmed.split(separator: " ")
            return words.count <= 4 && !trimmed.contains(where: \.isNumber)
        }

        let bodySource = extractedResumeDisplayText ?? rawExtracted
        let rawBodyLines = bodySource.components(separatedBy: .newlines)
        let lineFilteredBodyLines = rawBodyLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if linesToExclude.contains(trimmed) { return false }
            // The individual-field check above misses a combined "phone | email | location"
            // line (the whole line never exactly equals any one field) — the resume's original
            // contact line can appear in a different field order than the `contactLine` string
            // built above, so anchor on the email alone: it's unique enough that any line
            // containing it is virtually always the contact line, regardless of field order.
            if let email = extractedEmail, !email.isEmpty, trimmed.contains(email) { return false }
            if looksLikeDuplicateNameLine(trimmed) { return false }
            return true
        }
        // The summary itself can reappear wrapped across several separate lines (rather than
        // one line matching `summary` verbatim) — a per-line exact/substring check above can't
        // catch that, since no single line equals the whole joined summary. Greedily grow a
        // window of consecutive lines and drop the whole window once it reconstructs a
        // meaningful chunk of the summary text.
        var dedupedBodyLines: [String] = []
        var index = 0
        while index < lineFilteredBodyLines.count {
            if !summary.isEmpty {
                // Grows the window for as long as it keeps matching a substring of the summary
                // — stopping early at the first line that no longer fits would leave the rest
                // of that same duplicate block behind uncollapsed.
                var window = ""
                var lookahead = index
                while lookahead < lineFilteredBodyLines.count {
                    let candidateLine = lineFilteredBodyLines[lookahead].trimmingCharacters(in: .whitespaces)
                    guard !candidateLine.isEmpty else { break }
                    let candidateWindow = window.isEmpty ? candidateLine : window + " " + candidateLine
                    guard summary.contains(candidateWindow) else { break }
                    window = candidateWindow
                    lookahead += 1
                }
                if window.count >= min(summary.count, 60) {
                    index = lookahead
                    continue
                }
            }
            dedupedBodyLines.append(lineFilteredBodyLines[index])
            index += 1
        }
        let cleanedBody = ResumeSectionKit.removeDanglingHeaders(dedupedBodyLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = [name]
        if !role.isEmpty {
            lines.append(role)
        }
        if !contactLine.isEmpty {
            lines.append(contactLine)
        }
        lines.append("")
        if !summary.isEmpty {
            lines.append("SUMMARY")
            lines.append(summary)
            lines.append("")
        }
        lines.append(cleanedBody)

        return lines.joined(separator: "\n")
    }

    func coverLetterExportText() -> String {
        let name = experience.fullName.isEmpty ? "Jamie Chen" : experience.fullName
        let role = experience.currentRole.isEmpty ? "Product Designer" : experience.currentRole
        let skills = experience.skills.isEmpty ? "product design, user research, and prototyping" : experience.skills.joined(separator: ", ")
        let company = jobTarget.company.isEmpty ? "your company" : jobTarget.company
        let roleAtCompany = jobTarget.title.isEmpty ? "this role at \(company)" : "the \(jobTarget.title) role at \(company)"
        let workSummary = experience.workHistorySummary.isEmpty ? "My background has prepared me to take on new challenges" : experience.workHistorySummary
        let body = aiGeneratedCoverLetterBody ?? """
        I'm excited to apply for \(roleAtCompany). As a \(role) with \(experience.yearsOfExperience) of experience in \(skills), I'm confident I can make an immediate impact on your team.

        \(workSummary) and I'd welcome the chance to discuss how I can contribute to \(company)'s continued success.
        """
        return """
        Dear Hiring Manager,

        \(body)

        Sincerely,
        \(name)
        """
    }

    func jobFitExportText() -> String {
        guard let kit = applicationKit else { return "No job fit analysis available yet." }
        var lines = ["Job Fit Score: \(kit.jobFitScore)%", "", "Suggestions:"]
        for suggestion in kit.suggestions {
            lines.append("- \(suggestion.title)")
            if !suggestion.detail.isEmpty {
                lines.append("  \(suggestion.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
