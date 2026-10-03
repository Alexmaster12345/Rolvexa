import Foundation
import Testing
@testable import Rolvexa

/// Parsing resumes that aren't written in English.
///
/// Worth its own suite because the failure mode is silent: the all-caps heading test is
/// meaningless in a script with no case, so a Hebrew resume parsed without error and produced
/// nonsense — every short line a heading, no sections found, and a score docked for structure
/// the document actually had.
struct MultilingualParsingTests {
    static let hebrewResume = """
    ישראל ישראלי
    מהנדס תוכנה
    israel@example.com | 050-1234567 | תל אביב

    תקציר
    מהנדס תוכנה עם שבע שנות ניסיון בפיתוח מערכות.

    כישורים טכניים
    Linux, AWS, Python, Kubernetes

    ניסיון תעסוקתי
    מהנדס תוכנה בכיר | 2019 – היום
    חברת אקמי, תל אביב
    • בניתי שירותים מבוססי Kubernetes על AWS
    • הפחתתי זמן פריסה ב-40%

    השכלה
    תואר ראשון במדעי המחשב
    אוניברסיטת תל אביב
    """

    // MARK: - Caseless scripts

    @Test("Ordinary Hebrew lines are not mistaken for section headings", arguments: [
        "ישראל ישראלי",             // a name
        "מהנדס תוכנה בכיר",          // a job title
        "חברת אקמי, תל אביב",        // an employer line
        "• הפחתתי זמן פריסה ב-40%",  // a bullet
        "אוניברסיטת תל אביב"         // a university
    ])
    func hebrewBodyLinesAreNotHeadings(line: String) {
        // `line == line.uppercased()` is true for every one of these, which is why the
        // uppercase test alone classified all of them as headings.
        #expect(line == line.uppercased(), "precondition: Hebrew has no case")
        #expect(!ResumeSectionKit.isSectionHeader(line))
    }

    @Test("Real Hebrew section headings are recognised", arguments: [
        ("תקציר", "Summary"),
        ("כישורים טכניים", "Skills"),
        ("ניסיון תעסוקתי", "Experience"),
        ("השכלה", "Education"),
        ("פרויקטים", "Projects")
    ])
    func hebrewHeadingsAreRecognised(heading: String, section: String) {
        #expect(ResumeSectionKit.isSectionHeader(heading))
        #expect(ResumeSectionKit.detectedSections(in: "\(heading)\nתוכן כלשהו").contains(section))
    }

    @Test("A Hebrew resume isn't penalised for sections it actually has")
    func hebrewResumeScoresItsStructure() {
        // Previously this returned an empty set, so the scorer docked 8 points per "missing"
        // section for a resume that had all four.
        let sections = ResumeSectionKit.detectedSections(in: Self.hebrewResume)
        #expect(sections.isSuperset(of: ["Summary", "Skills", "Experience", "Education"]))
    }

    @Test("Only the four real headings are found, not every short line")
    func hebrewHeadingCountIsSane() {
        let headings = Self.hebrewResume
            .components(separatedBy: "\n")
            .filter { ResumeSectionKit.isSectionHeader($0) }
        #expect(headings.count == 4, "found: \(headings)")
    }

    @Test("English technology names are still mined from a Hebrew document")
    func mixedScriptSkillsAreFound() {
        // A resume written in Israel is routinely bilingual: Hebrew prose, English tooling.
        let skills = Set(ResumeSectionKit.extractSkills(from: Self.hebrewResume))
        #expect(skills.isSuperset(of: ["Linux", "AWS", "Python", "Kubernetes"]))
    }

    @Test("Other caseless scripts are handled the same way", arguments: [
        "株式会社アクメ",        // Japanese employer
        "소프트웨어 엔지니어",    // Korean job title
        "مهندس برمجيات"         // Arabic job title
    ])
    func otherCaselessScriptsAreNotAllHeadings(line: String) {
        #expect(!ResumeSectionKit.isSectionHeader(line))
    }

    // MARK: - Skill mining precision

    @Test("Single-letter skills aren't matched inside ordinary words")
    func skillMiningDoesNotFalsePositive() {
        // "C" lives inside "Charge", "R" inside "Registered" — this resume came back claiming
        // its author knew C and R.
        let nursing = """
        SARAH MILLER
        Registered Nurse

        EXPERIENCE
        Charge Nurse — County Hospital
        • Supervised a ward of twenty beds and coordinated discharge planning.
        """
        #expect(ResumeSectionKit.extractSkills(from: nursing).isEmpty)
    }

    @Test("Punctuated technology names still mine correctly")
    func punctuatedSkillsStillMatch() {
        let text = "NAME\n\nEXPERIENCE\nBuilt services in C++ and Go with Node.js and CI/CD."
        let skills = Set(ResumeSectionKit.extractSkills(from: text))
        #expect(skills.isSuperset(of: ["C++", "Go", "Node.js", "CI/CD"]))
        #expect(!skills.contains("C"), "C++ must not also register bare C")
    }

    @Test("Whole-term matching is shared, so it behaves identically everywhere", arguments: [
        ("R", "Worked in Paris", false),
        ("R", "Modelled in R and Python", true),
        ("Go", "Used Google Cloud", false),
        ("Go", "Wrote services in Go", true),
        ("AWS", "Deployed on AWS.", true),
        ("C", "Built in C++", false)
    ])
    func sharedTokenMatching(term: String, text: String, expected: Bool) {
        #expect(ResumeSectionKit.containsWholeTerm(term, in: text.lowercased()) == expected)
    }

    // MARK: - End to end

    @Test("A Hebrew resume exports without losing its content")
    @MainActor
    func hebrewResumeSurvivesExport() {
        let state = AppState()
        state.buildSource = .upload
        state.experience.fullName = "ישראל ישראלי"
        state.experience.currentRole = "מהנדס תוכנה"
        state.experience.skills = ["Linux", "AWS", "Python"]
        state.extractedEmail = "israel@example.com"
        state.extractedSummary = "מהנדס תוכנה עם שבע שנות ניסיון."
        state.updateExtractedResumeText(Self.hebrewResume)

        let exported = state.resumeExportText()
        for fragment in ["ישראל ישראלי", "מהנדס תוכנה", "אוניברסיטת תל אביב", "Kubernetes"] {
            #expect(exported.contains(fragment), "export dropped \(fragment)")
        }
    }
}
