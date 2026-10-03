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
