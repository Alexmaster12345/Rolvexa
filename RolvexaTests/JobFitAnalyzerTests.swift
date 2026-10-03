import Foundation
import Testing
@testable import Rolvexa

/// `JobFitAnalyzer` decides a number someone's job application depends on, so these cover not
/// just the happy path but the ways a match can be silently overstated.
struct JobFitAnalyzerTests {
    // MARK: - Fixtures

    static let sreposting = """
    Senior Site Reliability Engineer — Northwind Labs

    We are looking for a Senior SRE to own our production platform. You will run
    services on Kubernetes, manage infrastructure with Terraform, and automate
    deployments through CI/CD pipelines on AWS. Strong Python and Linux skills are
    required. Experience with Docker and monitoring is essential. You will partner
    with engineering teams on reliability, incident response and compliance.
    Reliability and compliance are central to this platform role.

    Requirements:
    - Bachelor degree in Computer Science or equivalent
    - Kubernetes, Terraform, AWS, Docker, Python, Linux
    """

    static let matchingResume = """
    ELLIOT ALDERSON
    Senior Infrastructure Engineer

    PROFESSIONAL EXPERIENCE
    Senior Infrastructure Engineer | 2019 – Present
    Allsafe
    • Ran containerised services on Kubernetes across three AWS regions
    • Automated deployments with CI/CD and Docker, improving platform reliability
    • Led incident response and compliance reviews

    SKILLS
    Python, Linux, Kubernetes, Docker, AWS, CI/CD, Terraform

    EDUCATION
    BSc Computer Science
    """

    private static func analyze(_ posting: String, _ resume: String, skills: [String] = []) -> JobFitAnalysis? {
        JobFitAnalyzer.analyze(jobDescription: posting, resumeText: resume, resumeSkills: skills)
    }

    // MARK: - Scoring

    @Test("A candidate meeting every stated requirement scores 100%")
    func perfectCandidateScoresFull() throws {
        let fit = try #require(Self.analyze(Self.sreposting, Self.matchingResume))
        #expect(fit.overallScore == 100)
        #expect(fit.summaryLabel == "Strong match")
        #expect(fit.missingSkills.isEmpty)
    }

    @Test("A single missing skill lowers the score without collapsing it")
    func oneGapScoresLower() throws {
        let withoutTerraform = Self.matchingResume.replacingOccurrences(of: ", Terraform", with: "")
        let fit = try #require(Self.analyze(Self.sreposting, withoutTerraform))
        #expect(fit.missingSkills == ["Terraform"])
        #expect(fit.overallScore > 80 && fit.overallScore < 100)
    }

    @Test("An unrelated candidate scores zero rather than a polite minimum")
    func unrelatedCandidateScoresZero() throws {
        let fit = try #require(Self.analyze(Self.sreposting, """
        JANE DOE
        Office Administrator
        • Managed scheduling and supplier records
        SKILLS
        Excel
        """))
        #expect(fit.overallScore == 0)
        #expect(fit.summaryLabel == "Weak match")
        #expect(fit.matchedSkills.isEmpty)
    }

    @Test("Skills are reported as matched and missing, not just counted")
    func matchedAndMissingAreEnumerated() throws {
        let withoutTerraform = Self.matchingResume.replacingOccurrences(of: ", Terraform", with: "")
        let fit = try #require(Self.analyze(Self.sreposting, withoutTerraform))
        #expect(Set(fit.matchedSkills).isSuperset(of: ["Python", "Linux", "Kubernetes", "Docker", "AWS"]))
        #expect(!fit.matchedSkills.contains("Terraform"))
    }

    @Test("Every component carries the counts behind its percentage")
    func componentsExplainThemselves() throws {
        let fit = try #require(Self.analyze(Self.sreposting, Self.matchingResume))
        #expect(!fit.components.isEmpty)
        for component in fit.components {
            #expect(!component.detail.isEmpty, "\(component.title) has no explanation")
            #expect((0...100).contains(component.percent))
        }
    }

    @Test("The same inputs always produce the same score")
    func scoringIsDeterministic() throws {
        let scores = (0..<5).map { _ in Self.analyze(Self.sreposting, Self.matchingResume)?.overallScore }
        #expect(Set(scores.map { $0 ?? -1 }).count == 1)
    }

    // MARK: - Weight redistribution

    @Test("A posting with no degree requirement doesn't penalise a resume without one")
    func unstatedRequirementsAreNotScored() throws {
        let posting = "Backend engineer needed. Must know Python, Docker and PostgreSQL to build our services."
        let resume = "Engineer\nSKILLS\nPython, Docker, PostgreSQL"
        let fit = try #require(Self.analyze(posting, resume))
        #expect(fit.overallScore == 100, "no degree was asked for, so its absence must not cost anything")
        #expect(!fit.components.contains { $0.title == "Education" })
    }

    // MARK: - Term matching

    @Test("Single-letter skills don't match inside ordinary words", arguments: [
        ("R", "Worked in Paris on research projects for the group."),
        ("C", "Coordinated a cross-functional company initiative."),
        ("Go", "Used Google services throughout the organisation.")
    ])
    func shortSkillsRequireWordBoundaries(skill: String, resume: String) throws {
        let posting = "We need \(skill) experience for this data engineering position at our company today."
        let fit = try #require(Self.analyze(posting, resume))
        #expect(fit.matchedSkills.isEmpty, "\(skill) should not match inside a longer word")
    }

    @Test("A posting asking for C++ does not also register a requirement for C")
    func plusSuffixedSkillsAreDistinct() throws {
        let fit = try #require(Self.analyze(
            "Looking for C++ and CI/CD and Node.js experience across our backend team today.",
            "Built services in C++ with CI/CD pipelines and a Node.js gateway layer."
        ))
        // Without treating "+" as part of the token, bare C is extracted as a second
        // requirement that the resume's own "C++" then satisfies, inflating the match.
        #expect(!fit.matchedSkills.contains("C"))
        #expect(Set(fit.matchedSkills) == ["C++", "CI/CD", "Node.js"])
    }

    @Test("A skill at the end of a sentence still matches")
    func trailingPunctuationDoesNotBlockMatches() throws {
        let fit = try #require(Self.analyze(
            "The successful engineer will deploy our production services on AWS. Docker required too.",
            "Deployed production workloads to AWS and packaged everything with Docker."
        ))
        #expect(Set(fit.matchedSkills) == ["AWS", "Docker"])
    }

    @Test("Skills listed only in the skills array, not the prose, still count")
    func resumeSkillsArrayIsSearched() throws {
        let fit = try #require(Self.analyze(
            "Backend role. Must know Python and Docker and PostgreSQL for our growing services.",
            "Engineer with a long career.",
            skills: ["Python", "Docker", "PostgreSQL"]
        ))
        #expect(fit.missingSkills.isEmpty)
    }

    // MARK: - Refusing to answer

    @Test("No analysis is produced without a posting to compare against", arguments: [
        "",
        "   \n  ",
        "SRE wanted."
    ])
    func absentOrTinyPostingsYieldNothing(posting: String) {
        #expect(Self.analyze(posting, Self.matchingResume) == nil)
    }

    @Test("Gibberish yields no analysis rather than a confident zero")
    func unanalysablePostingYieldsNothing() {
        // Long enough to pass the length check, but containing no recognisable requirement —
        // this previously scored 0% off nothing but its own repeated nonsense.
        let noise = String(repeating: "aaaa bbbb cccc dddd ", count: 5)
        #expect(Self.analyze(noise, Self.matchingResume) == nil)
    }

    @Test("Prose with no concrete requirement yields no analysis")
    func themeOnlyPostingYieldsNothing() {
        let posting = "We value teamwork and teamwork and collaboration and collaboration in our friendly group."
        #expect(Self.analyze(posting, Self.matchingResume) == nil)
    }

    // MARK: - Keyword fairness

    @Test("Boilerplate and words scored elsewhere are excluded from keywords")
    func keywordsExcludeNoiseAndDoubleCounting() throws {
        let fit = try #require(Self.analyze(Self.sreposting, Self.matchingResume))
        let keywords = Set(fit.matchedKeywords + fit.missingKeywords)
        // "bachelor"/"degree" are scored by the Education component and "senior" by Seniority;
        // counting them here charged twice for one gap.
        #expect(keywords.isDisjoint(with: ["bachelor", "degree", "senior", "looking", "required", "essential"]))
    }

    @Test("A full skills match isn't dragged down by incidental keywords")
    func keywordNoiseDoesNotPenaliseAStrongMatch() throws {
        // Every stated skill is present; the score should reflect that rather than being
        // pulled under by one-off words like "today" or "across".
        let fit = try #require(Self.analyze(
            "Looking for C++ and CI/CD and Node.js experience across our backend team today.",
            "Built services in C++ with CI/CD pipelines and a Node.js gateway layer."
        ))
        #expect(fit.overallScore == 100)
    }

    // MARK: - Labels

    @Test("Score bands map to the labels the UI shows", arguments: [
        (100, "Strong match"), (85, "Strong match"),
        (84, "Good match"), (70, "Good match"),
        (69, "Partial match"), (50, "Partial match"),
        (49, "Weak match"), (0, "Weak match")
    ])
    func summaryLabelBands(score: Int, expected: String) {
        let analysis = JobFitAnalysis(
            overallScore: score, components: [], matchedSkills: [],
            missingSkills: [], matchedKeywords: [], missingKeywords: []
        )
        #expect(analysis.summaryLabel == expected)
    }
}
