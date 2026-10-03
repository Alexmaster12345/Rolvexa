import Foundation
import Testing
@testable import Rolvexa

/// Covers what `resumeExportText()` puts in front of the user — including the cases where the
/// honest answer is an empty section.
@MainActor
struct ResumeExportTextTests {
    // MARK: - Fixtures

    private static func filledWriteFlowState() -> AppState {
        let state = AppState()
        state.buildSource = .write
        state.experience.fullName = "Priya Singh"
        state.experience.currentRole = "Facility Property Manager"
        state.experience.email = "priya@example.com"
        state.experience.phone = "(123) 456-7890"
        state.experience.location = "San Jose, CA"
        state.experience.linkedIn = "linkedin.com/in/priyasingh"
        state.experience.skills = ["Preventive Maintenance", "CAFM Software"]

        var job = WorkExperienceEntry()
        job.title = "Facility Property Manager"
        job.company = "Silicon Valley Tech Park"
        job.location = "San Jose, CA"
        job.startDate = "Feb 2017"
        job.isCurrent = true
        job.bullets = ["Cut unplanned downtime by 30%"]
        state.experience.positions = [job]

        var school = EducationEntry()
        school.degree = "BSc Mechanical Engineering"
        school.school = "San Jose State University"
        school.graduationDate = "May 2013"
        state.experience.educationEntries = [school]
        return state
    }

    private static func headings(of text: String) -> [String] {
        text.components(separatedBy: "\n")
            .filter { ResumeSectionKit.isSectionHeader($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Structure

    @Test("Sections appear in the order the preview card shows them")
    func sectionOrderMatchesThePreview() {
        let text = Self.filledWriteFlowState().resumeExportText()
        #expect(Self.headings(of: text) == ["ABOUT ME", "PROFESSIONAL EXPERIENCE", "SKILLS", "EDUCATION"])
    }

    @Test("Renaming SUMMARY to ABOUT ME keeps the scorer's section detection working")
    func scorerStillDetectsEverySection() {
        let sections = ResumeSectionKit.detectedSections(in: Self.filledWriteFlowState().resumeExportText())
        #expect(sections == ["Summary", "Experience", "Skills", "Education"])
    }

    @Test("Each job prints its heading, employer and bullets")
    func jobsPrintStructured() {
        let text = Self.filledWriteFlowState().resumeExportText()
        #expect(text.contains("Facility Property Manager | Feb 2017 – Present"))
        #expect(text.contains("Silicon Valley Tech Park, San Jose, CA"))
        #expect(text.contains("• Cut unplanned downtime by 30%"))
    }

    @Test("Profile links join the contact line")
    func linksAppearInContactLine() {
        let text = Self.filledWriteFlowState().resumeExportText()
        let contactLine = text.components(separatedBy: "\n").first { $0.contains("@") }
        #expect(contactLine?.contains("linkedin.com/in/priyasingh") == true)
    }

    @Test("A current role prints Present rather than a blank end date")
    func currentRolePrintsPresent() {
        var job = WorkExperienceEntry()
        job.title = "Engineer"
        job.company = "Acme"
        job.startDate = "2020"
        job.isCurrent = true
        job.bullets = ["Did the work"]
        #expect(job.dateRange == "2020 – Present")
        #expect(job.headingLine == "Engineer | 2020 – Present")
    }

    // MARK: - Summary precedence

    @Test("A hand-written summary wins over the generated sentence")
    func writtenSummaryOverridesGenerated() {
        let state = Self.filledWriteFlowState()
        state.experience.summary = "Facilities leader who keeps 1M sq ft running."
        let text = state.resumeExportText()
        #expect(text.contains("Facilities leader who keeps 1M sq ft running."))
        #expect(!text.contains("Seeking to bring this expertise"))
    }

    @Test("The generated summary names the target role when one was entered")
    func generatedSummaryUsesJobTarget() {
        let state = Self.filledWriteFlowState()
        state.jobTarget.title = "Senior Facilities Manager"
        state.jobTarget.company = "Northwind Labs"
        #expect(state.resumeExportText().contains("the Senior Facilities Manager role at Northwind Labs"))
    }

    @Test("The cover letter picks the right indefinite article", arguments: [
        ("Operations Manager", "As an Operations Manager"),
        ("Product Designer", "As a Product Designer"),
        ("Architect", "As an Architect"),
        // Initialisms are read letter by letter, so the letter's name decides: "eye-tee"
        // takes "an", "you-ex" takes "a".
        ("IT Manager", "As an IT Manager"),
        ("UX Researcher", "As a UX Researcher"),
        ("HR Partner", "As an HR Partner"),
        ("QA Engineer", "As a QA Engineer"),
        // Vowel letter, consonant sound.
        ("University Lecturer", "As a University Lecturer"),
        ("European Sales Lead", "As a European Sales Lead")
    ])
    func coverLetterArticleAgreement(role: String, expected: String) {
        let state = AppState()
        state.buildSource = .write
        state.experience.fullName = "Jane Doe"
        state.experience.currentRole = role
        state.experience.skills = ["Reporting"]
        #expect(state.coverLetterExportText().contains(expected))
    }

    // MARK: - Never inventing content

    @Test("An upload whose extraction failed produces no invented person")
    func failedExtractionInventsNothing() {
        // `resumeExportText()` falls through to the write branch when extraction returns nil.
        // The Review screen reports "We couldn't read this file" but still lets the user
        // continue, so this path is reachable — and used to emit a complete, confident resume
        // for a fictional "Jamie Chen, Product Designer".
        let state = AppState()
        state.buildSource = .upload
        state.extractedResumeText = nil
        state.uploadedFileName = "scan.pdf"

        let resume = state.resumeExportText()
        let letter = state.coverLetterExportText()
        for invented in ["Jamie Chen", "Product Designer", "Figma", "User Research", "prototyping"] {
            #expect(!resume.contains(invented), "resume invented \(invented)")
            #expect(!letter.contains(invented), "cover letter invented \(invented)")
        }
    }

    @Test("Placeholder prompts never reach the exported file")
    func placeholderPromptsAreNotExported() {
        let state = AppState()
        state.buildSource = .write
        #expect(!state.resumeExportText().contains("Add your work history to see it tailored here."))
    }

    @Test("Empty sections are omitted rather than printed with stand-in text")
    func emptySectionsAreOmitted() {
        let state = AppState()
        state.buildSource = .write
        state.experience.fullName = "Sam Reed"
        let headings = Self.headings(of: state.resumeExportText())
        #expect(!headings.contains("SKILLS"))
        #expect(!headings.contains("PROFESSIONAL EXPERIENCE"))
        #expect(!headings.contains("EDUCATION"))
    }

    @Test("Skills no longer default to sample values")
    func skillsStartEmpty() {
        #expect(ExperienceInput().skills.isEmpty)
    }

    // MARK: - Completeness gates

    @Test("A job without a company or a bullet is incomplete and isn't exported")
    func incompletePositionsAreExcluded() {
        var titleOnly = WorkExperienceEntry()
        titleOnly.title = "Analyst"
        #expect(!titleOnly.isComplete)

        var noBullets = WorkExperienceEntry()
        noBullets.title = "Analyst"
        noBullets.company = "Acme"
        #expect(!noBullets.isComplete)

        var complete = WorkExperienceEntry()
        complete.title = "Analyst"
        complete.company = "Acme"
        complete.bullets = ["Did the work"]
        #expect(complete.isComplete)
    }

    @Test("Blank bullets are dropped, not exported as empty list items")
    func blankBulletsAreDropped() {
        var job = WorkExperienceEntry()
        job.bullets = ["Real achievement", "   ", ""]
        #expect(job.filledBullets == ["Real achievement"])
    }

    // MARK: - Uploaded resumes

    @Test("An uploaded resume with its own skills heading doesn't get a second one")
    func uploadedSkillsSectionIsNotDuplicated() {
        // The written-back SKILLS block exists so the sidebar layouts can find one. When the
        // uploaded file already had "TECHNICAL SKILLS", single-column templates printed the
        // identical list twice under two headings.
        let state = AppState()
        state.buildSource = .upload
        state.experience.fullName = "Elliot Alderson"
        state.experience.skills = ["Python", "Linux"]
        state.extractedEmail = "elliot@example.com"
        state.extractedSummary = "Security analyst."
        state.updateExtractedResumeText("""
        ELLIOT ALDERSON
        Security Analyst
        elliot@example.com

        TECHNICAL SKILLS
        Python, Linux

        EXPERIENCE
        Analyst — Allsafe
        • Hardened systems.
        """)

        let skillHeadings = Self.headings(of: state.resumeExportText())
            .filter { $0.contains("SKILL") }
        #expect(skillHeadings.count == 1)
    }
}
