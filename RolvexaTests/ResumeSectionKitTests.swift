import Foundation
import Testing
@testable import Rolvexa

/// Section detection and keyword mining — the parsing layer every other feature reads through.
struct ResumeSectionKitTests {
    // MARK: - Section headers

    @Test("All-caps short lines are headers", arguments: [
        "EXPERIENCE", "TECHNICAL SKILLS", "ABOUT ME", "EDUCATION"
    ])
    func recognisesHeaders(line: String) {
        #expect(ResumeSectionKit.isSectionHeader(line))
    }

    @Test("Ordinary prose and short fragments are not headers", arguments: [
        "Managed a team of five engineers",
        "Python, Linux, Docker",
        "ab",
        "   ",
        "1234"
    ])
    func rejectsNonHeaders(line: String) {
        #expect(!ResumeSectionKit.isSectionHeader(line))
    }

    @Test("Letter-spaced headers from PDF extraction still resolve to a section")
    func letterSpacedHeadersAreDetected() {
        // Many templates render headings with letter-spacing, which extraction reproduces as
        // literal spaces between every character.
        #expect(ResumeSectionKit.detectedSections(in: "E D U C A T I O N\nBSc").contains("Education"))
    }

    @Test("ABOUT ME counts as the summary section")
    func aboutMeIsASummary() {
        // The exports use this heading to match the preview card; section-completeness scoring
        // has to keep recognising it.
        #expect(ResumeSectionKit.detectedSections(in: "ABOUT ME\nA short bio.").contains("Summary"))
    }

    @Test("Section synonyms resolve to the same canonical name", arguments: [
        ("PROFESSIONAL SUMMARY", "Summary"),
        ("PROFILE", "Summary"),
        ("EMPLOYMENT HISTORY", "Experience"),
        ("ACADEMIC BACKGROUND", "Education"),
        ("CORE COMPETENCIES", "Skills"),
        ("CERTIFICATIONS", "Certifications")
    ])
    func synonymsResolve(heading: String, section: String) {
        #expect(ResumeSectionKit.detectedSections(in: "\(heading)\nbody text").contains(section))
    }

    // MARK: - Keyword extraction

    @Test("Keyword extraction returns results even without the part-of-speech model")
    func keywordExtractionAlwaysProduces() {
        // Where the lexical-class model isn't present every token comes back tagged
        // `.otherWord`, and this returned an empty array on every input — silently disabling
        // keyword extraction rather than degrading it.
        let keywords = ResumeSectionKit.extractKeywords(from: """
        Reliability and compliance drive our platform. Reliability and compliance matter here.
        Platform teams own reliability across the estate.
        """, limit: 5)
        #expect(!keywords.isEmpty)
        #expect(keywords.contains("reliability"))
    }

    @Test("Repeated calls return the same list in the same order")
    func keywordExtractionIsStable() {
        let text = "Platform reliability and compliance. Platform compliance and reliability engineering."
        let runs = (0..<5).map { _ in ResumeSectionKit.extractKeywords(from: text, limit: 6) }
        #expect(Set(runs.map { $0.joined(separator: ",") }).count == 1)
    }

    @Test("Stopwords and very short tokens are excluded")
    func keywordsExcludeNoise() {
        let keywords = ResumeSectionKit.extractKeywords(from: """
        The the the and and and with with with for for for role role team team work work.
        """, limit: 10)
        #expect(keywords.isDisjoint(with: ["the", "and", "with", "for", "role", "team", "work"]))
    }

    @Test("The limit is respected")
    func keywordLimitIsHonoured() {
        let text = (1...40).map { "distinctword\($0) distinctword\($0)" }.joined(separator: " ")
        #expect(ResumeSectionKit.extractKeywords(from: text, limit: 7).count <= 7)
    }

    // MARK: - Skills

    @Test("A skills section is parsed into individual entries")
    func skillsSectionIsSplit() {
        let skills = ResumeSectionKit.extractSkills(from: """
        NAME HERE

        TECHNICAL SKILLS
        Python, Linux, Docker

        EXPERIENCE
        Did things.
        """)
        #expect(Set(skills).isSuperset(of: ["Python", "Linux", "Docker"]))
    }

    @Test("With no skills heading, known skills are mined from the body")
    func skillsFallBackToKeywordMining() {
        let skills = ResumeSectionKit.extractSkills(from: """
        NAME HERE

        EXPERIENCE
        Built services with Python and Docker on AWS infrastructure.
        """)
        #expect(Set(skills).isSuperset(of: ["Python", "Docker", "AWS"]))
    }

    // MARK: - Links

    @Test("Profile links are recognised", arguments: [
        "linkedin.com/in/someone",
        "github.com/someone",
        "www.linkedin.com/in/someone"
    ])
    func extractsProfileLinks(link: String) {
        #expect(ResumeSectionKit.extractLinks(from: "Contact: \(link) for details").contains { $0.contains(link) })
    }
}

private extension Array where Element == String {
    func isDisjoint(with other: [String]) -> Bool {
        Set(self).isDisjoint(with: Set(other))
    }
}
