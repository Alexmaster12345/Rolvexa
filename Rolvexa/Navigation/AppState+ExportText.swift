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
            if isKeepingOriginalUploadedLayout {
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
        // No invented stand-ins for missing values.
        //
        // This branch isn't only reached by the validated write-from-scratch form: an upload
        // whose text extraction returns nil falls through to here too (the Review screen shows
        // "We couldn't read this file" but still lets you continue). With sample defaults in
        // place that produced a complete, confident resume for a fictional "Jamie Chen, Product
        // Designer" — a fabricated document under the user's own download button. An empty
        // section is a far better failure than a convincing wrong one.
        let name = experience.fullName.isEmpty
            ? (uploadedFileName ?? "Your Resume")
            : experience.fullName
        let role = experience.currentRole
        let skills = experience.skills.joined(separator: ", ")
        let summary = resolvedSummary(role: role, skills: skills)
        // Profile links sit in the contact line, which every template renders as the CONTACT
        // block — the same shape the upload flow produces.
        let contactLine = ([experience.email, experience.phone, experience.location] + experience.links)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        var lines: [String] = [name]
        if !role.isEmpty { lines.append(role) }
        if !contactLine.isEmpty { lines.append(contactLine) }
        lines.append("")
        // "ABOUT ME" rather than "SUMMARY" to match the heading every `ResumeTemplateCard`
        // layout shows on screen. `ResumeSectionKit.standardSectionKeywords` already lists
        // "ABOUTME" under Summary, so section-completeness scoring is unaffected.
        if let summary {
            lines.append("ABOUT ME")
            lines.append(summary)
        }

        // Experience before skills, matching the card. The sidebar and banner layouts hoist
        // SKILLS into their coloured region regardless, so this only changes the single-column
        // templates — which are exactly the ones that disagreed with the preview.
        //
        // Each job prints as heading / employer / bullets, with a blank line between jobs, so the
        // exported PROFESSIONAL EXPERIENCE section matches what a real resume template shows
        // rather than collapsing into one paragraph.
        let positions = experience.completedPositions
        if !positions.isEmpty {
            lines.append("")
            lines.append("PROFESSIONAL EXPERIENCE")
            for (index, position) in positions.enumerated() {
                if index > 0 { lines.append("") }
                lines.append(position.headingLine)
                if !position.employerLine.isEmpty { lines.append(position.employerLine) }
                lines.append(contentsOf: position.filledBullets.map { "• \($0)" })
            }
        }

        if !skills.isEmpty {
            lines.append("")
            lines.append("SKILLS")
            lines.append(skills)
        }

        let education = experience.completedEducation
        if !education.isEmpty {
            lines.append("")
            lines.append("EDUCATION")
            for (index, entry) in education.enumerated() {
                if index > 0 { lines.append("") }
                lines.append(contentsOf: entry.displayLines)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Precedence for the "About me" paragraph: what the user wrote, else what the AI pass
    /// produced, else a sentence generated from the role and skills.
    ///
    /// Returns nil when there's nothing truthful to build it from, so the caller drops the
    /// section rather than printing a sentence about an unnamed role and no skills.
    private func resolvedSummary(role: String, skills: String) -> String? {
        let written = experience.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !written.isEmpty { return written }
        if let aiGeneratedSummary { return aiGeneratedSummary }
        guard !role.isEmpty, !skills.isEmpty else { return nil }
        return "\(role) with \(experience.yearsOfExperience) of experience, skilled in \(skills). Seeking to bring this expertise to \(targetRoleAtCompany)."
    }

    /// "the Facility Manager role at Acme", or a neutral fallback when no target was entered.
    var targetRoleAtCompany: String {
        let company = jobTarget.company.isEmpty ? "your company" : jobTarget.company
        // "this role" already reads as a full phrase on its own — appending the literal word
        // "role" after it (as the non-empty-title branch needs) would read "this role role".
        return jobTarget.title.isEmpty ? "this role at \(company)" : "the \(jobTarget.title) role at \(company)"
    }

    /// Reassembles an uploaded resume's extracted text into the same sane order the in-app
    /// preview (`ResumeTemplateCard`) already presents it in: name/role/contact up top, then the
    /// summary, then the rest of the body with dangling section headers (no body under them —
    /// their real content extracted elsewhere) removed.
    private func structuredUploadExportText(rawExtracted: String) -> String {
        let name = experience.fullName.isEmpty ? (uploadedFileName ?? "Your Resume") : experience.fullName
        let role = experience.currentRole
        // Profile links join the contact details rather than sitting in a loose "LINKS" section
        // in the body — the templates render this whole line as the contact block.
        let contactLine = ([extractedEmail, extractedPhone, extractedLocation].compactMap { $0 } + extractedLinks)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let summary = extractedSummary ?? ""

        // Re-filter by content even though `extractedResumeDisplayText` should already be
        // stripped: that upstream pass can only remove what it recognized, so anything it missed
        // would print once in the header block below and again in the body.
        let cleanedBody = ResumeSectionKit.removingHeaderBlock(
            from: extractedResumeDisplayText ?? rawExtracted,
            name: name,
            role: role,
            summary: summary,
            email: extractedEmail,
            phone: extractedPhone,
            location: extractedLocation
        )

        var lines: [String] = [name]
        if !role.isEmpty {
            lines.append(role)
        }
        if !contactLine.isEmpty {
            lines.append(contactLine)
        }
        lines.append("")
        if !summary.isEmpty {
            // Matches the preview card's heading — see the note in `resumeExportText()`.
            lines.append("ABOUT ME")
            lines.append(summary)
            lines.append("")
        }
        // The skills were parsed out of the resume into `experience.skills` at upload, and the
        // preview takes them from there as a direct parameter. The exporters have no such
        // parameter — they recover skills by looking for a SKILLS heading in this text — so
        // without writing the section back out, the sidebar's "TECHNICAL SKILLS" list rendered
        // on screen was simply absent from every downloaded PDF and Word file.
        //
        // Only when the resume didn't bring its own, though. The sidebar and banner layouts hoist
        // every SKILL-ish section into one de-duplicated list, which hid the problem, but the
        // single-column layouts print the body verbatim — so an uploaded resume that already had
        // a "TECHNICAL SKILLS" heading got the identical list printed twice, under two headings.
        let bodyHasSkillsSection = cleanedBody
            .components(separatedBy: .newlines)
            .contains { ResumeSectionKit.isSectionHeader($0) && $0.uppercased().contains("SKILL") }
        if !experience.skills.isEmpty, !bodyHasSkillsSection {
            lines.append("SKILLS")
            lines.append(experience.skills.joined(separator: ", "))
            lines.append("")
        }
        lines.append(cleanedBody)

        return lines.joined(separator: "\n")
    }

    func coverLetterExportText() -> String {
        // Same no-invention rule as the resume: with nothing entered this used to produce a
        // confident letter from "Jamie Chen, Product Designer".
        let name = experience.fullName.isEmpty ? "" : experience.fullName
        let role = experience.currentRole
        let skills = experience.skills.joined(separator: ", ")
        let company = jobTarget.company.isEmpty ? "your company" : jobTarget.company
        let roleAtCompany = targetRoleAtCompany
        let highlights = experience.coverLetterHighlights
        let highlightSentence = highlights.isEmpty
            ? "My background has prepared me to take on new challenges."
            : "Recent highlights: \(highlights)."
        // The opening sentence only claims a role and skills when there are some to claim.
        let credentials = [
            role.isEmpty ? nil : "a \(role) with \(experience.yearsOfExperience) of experience",
            skills.isEmpty ? nil : "skills in \(skills)"
        ].compactMap { $0 }.joined(separator: " and ")
        let opening = credentials.isEmpty
            ? "I'm excited to apply for \(roleAtCompany), and I'm confident I can make an immediate impact on your team."
            : "I'm excited to apply for \(roleAtCompany). As \(credentials), I'm confident I can make an immediate impact on your team."
        let body = aiGeneratedCoverLetterBody ?? """
        \(opening)

        \(highlightSentence) I'd welcome the chance to discuss how I can contribute to \(company)'s continued success.
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
