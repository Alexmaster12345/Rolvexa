import Foundation

/// Builds the plain-text resume that both the preview and the PDF/Word exporters consume.
///
/// Lifted out of `AppState` so it can be called without one. A saved resume in the library is
/// structured data on disk, not a live session, and sharing one has to produce the *same*
/// document the user would have downloaded in-app — not a second, slightly different renderer
/// that drifts from the first.
nonisolated enum ResumeExportText {

    /// Assembles a resume from the structured fields alone.
    ///
    /// - Parameters:
    ///   - fallbackName: shown in place of a name when none was entered — the uploaded file's
    ///     name, usually. Deliberately a parameter rather than a constant: this function must
    ///     never invent an identity.
    ///   - aiSummary: the on-device model's "About me", used only when the user wrote none.
    static func fromStructuredInput(
        experience: ExperienceInput,
        jobTarget: JobTarget,
        aiSummary: String? = nil,
        fallbackName: String? = nil
    ) -> String {
        // No invented stand-ins for missing values.
        //
        // This isn't only reached by the validated write-from-scratch form: an upload whose text
        // extraction returns nil falls through to here too (the Review screen shows "We couldn't
        // read this file" but still lets you continue). With sample defaults in place that
        // produced a complete, confident resume for a fictional "Jamie Chen, Product Designer" —
        // a fabricated document under the user's own download button. An empty section is a far
        // better failure than a convincing wrong one.
        let name = experience.fullName.isEmpty
            ? (fallbackName ?? "Your Resume")
            : experience.fullName
        let role = experience.currentRole
        let skills = experience.skills.joined(separator: ", ")
        let summary = resolvedSummary(
            experience: experience, jobTarget: jobTarget, role: role, skills: skills,
            aiSummary: aiSummary
        )
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

    /// Whether an assembled resume is worth handing to anyone.
    ///
    /// A resume with no section at all is a name, maybe a job title, and blank space below.
    /// Offering to share that would let someone send a recruiter an empty page believing it was
    /// their resume — so "has at least one real section" is the bar, and it's the same bar the
    /// scorer already uses to decide a document has structure.
    static func hasBodyWorthSharing(_ body: String) -> Bool {
        body
            .components(separatedBy: .newlines)
            .contains { ResumeSectionKit.isSectionHeader($0) }
    }

    /// The structural form of the same question, for callers holding fields rather than text.
    ///
    /// Agrees with ``hasBodyWorthSharing(_:)`` by construction: any one of these produces a
    /// section heading in the assembled output.
    static func hasShareableContent(experience: ExperienceInput) -> Bool {
        !experience.completedPositions.isEmpty
            || !experience.completedEducation.isEmpty
            || !experience.skills.isEmpty
            || !experience.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "the Facility Manager role at Acme", or a neutral fallback when no target was entered.
    static func targetRoleAtCompany(_ jobTarget: JobTarget) -> String {
        let company = jobTarget.company.isEmpty ? "your company" : jobTarget.company
        // "this role" already reads as a full phrase on its own — appending the literal word
        // "role" after it (as the non-empty-title branch needs) would read "this role role".
        return jobTarget.title.isEmpty ? "this role at \(company)" : "the \(jobTarget.title) role at \(company)"
    }

    /// Precedence for the "About me" paragraph: what the user wrote, else what the AI pass
    /// produced, else a sentence generated from the role and skills.
    ///
    /// Returns nil when there's nothing truthful to build it from, so the caller drops the
    /// section rather than printing a sentence about an unnamed role and no skills.
    private static func resolvedSummary(
        experience: ExperienceInput,
        jobTarget: JobTarget,
        role: String,
        skills: String,
        aiSummary: String?
    ) -> String? {
        let written = experience.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !written.isEmpty { return written }
        if let aiSummary { return aiSummary }
        guard !role.isEmpty, !skills.isEmpty else { return nil }
        return "\(role) with \(experience.yearsOfExperience) of experience, skilled in \(skills). Seeking to bring this expertise to \(targetRoleAtCompany(jobTarget))."
    }
}
