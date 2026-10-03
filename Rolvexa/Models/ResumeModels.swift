import Foundation

enum JobLevel: String, CaseIterable, Identifiable {
    case entry = "Entry"
    case mid = "Mid"
    case senior = "Senior"
    case lead = "Lead"

    var id: String { rawValue }
}

struct JobTarget {
    var descriptionText: String = ""
    var title: String = ""
    var company: String = ""
    var level: JobLevel = .senior
}

/// One job on the resume, structured the way real resume templates print it: a title and date
/// range on one line, the employer and its location on the next, then bulleted achievements.
///
/// This replaces a single free-text "work history" box. That box exported as one run-on
/// paragraph under EXPERIENCE with no employer, no dates and no bullets — the biggest structural
/// gap between a generated resume and a real one, and the part recruiters and ATS parsers read
/// most closely.
struct WorkExperienceEntry: Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var company: String = ""
    var location: String = ""
    var startDate: String = ""
    var endDate: String = ""
    /// Prints "Present" as the end date and hides the end-date field while set.
    var isCurrent: Bool = false
    var bullets: [String] = [""]

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    var trimmedCompany: String { company.trimmingCharacters(in: .whitespaces) }

    var filledBullets: [String] {
        bullets
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var dateRange: String {
        let start = startDate.trimmingCharacters(in: .whitespaces)
        let end = isCurrent ? "Present" : endDate.trimmingCharacters(in: .whitespaces)
        if start.isEmpty { return end }
        if end.isEmpty { return start }
        return "\(start) – \(end)"
    }

    /// "Company, City, ST" — whichever parts were filled in.
    var employerLine: String {
        [trimmedCompany, location.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// A job needs at minimum who you were and where, plus one thing you did there.
    var isComplete: Bool {
        !trimmedTitle.isEmpty && !trimmedCompany.isEmpty && !filledBullets.isEmpty
    }

    /// The heading line: "Facility Property Manager | Feb 2017 – Present".
    var headingLine: String {
        dateRange.isEmpty ? trimmedTitle : "\(trimmedTitle) | \(dateRange)"
    }
}

/// One school, structured the way resume templates print it: degree, then school and location,
/// then the graduation date.
struct EducationEntry: Identifiable, Hashable {
    var id = UUID()
    var degree: String = ""
    var school: String = ""
    var location: String = ""
    var graduationDate: String = ""

    var trimmedDegree: String { degree.trimmingCharacters(in: .whitespaces) }
    var trimmedSchool: String { school.trimmingCharacters(in: .whitespaces) }

    var isComplete: Bool { !trimmedDegree.isEmpty && !trimmedSchool.isEmpty }

    /// "School, City, ST" — whichever parts were filled in.
    var schoolLine: String {
        [trimmedSchool, location.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var displayLines: [String] {
        [trimmedDegree, schoolLine, graduationDate.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
    }
}

struct ExperienceInput {
    var fullName: String = ""
    var currentRole: String = ""
    var yearsOfExperience: String = "5–7 years"
    // Starts empty rather than pre-seeded with sample skills. Those defaults were real data as
    // far as the exporters were concerned, so any path that reached a download without the user
    // entering skills produced a file claiming they knew Product Design, Figma and User Research.
    var skills: [String] = []
    var email: String = ""
    var phone: String = ""
    var location: String = ""
    /// Profile links. The upload flow has always parsed these out of an uploaded file into
    /// `AppState.extractedLinks` and rendered them in the CONTACT block; the write flow had no
    /// way to supply them, so a written resume could never show a LinkedIn.
    var linkedIn: String = ""
    var portfolio: String = ""
    /// Optional hand-written "About me". When empty, the generated template sentence is used.
    var summary: String = ""
    /// An optional headshot, already centre-cropped square and re-encoded as JPEG by
    /// `ResumePhoto.prepare(from:)`. Rendered as a circle in the sidebar template, on screen and
    /// in both exported formats.
    var photoData: Data?
    var positions: [WorkExperienceEntry] = [WorkExperienceEntry()]
    var educationEntries: [EducationEntry] = [EducationEntry()]

    var links: [String] {
        [linkedIn, portfolio]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var completedPositions: [WorkExperienceEntry] { positions.filter(\.isComplete) }
    var completedEducation: [EducationEntry] { educationEntries.filter(\.isComplete) }

    /// Every achievement bullet across every job, flattened.
    ///
    /// The cover letter, the job-title suggester and the grammar pass all want the work history
    /// as plain prose rather than as structure, and this is the single place that shape is
    /// derived — so the structured entries stay the one source of truth.
    var workHistorySummary: String {
        completedPositions.flatMap(\.filledBullets).joined(separator: " ")
    }

    /// Up to two achievements from the most recent job, for the cover letter.
    ///
    /// Deliberately not the full `workHistorySummary`: flattening every bullet from every job
    /// into the cover letter's sentence produced a six-clause run-on. A short "Recent
    /// highlights: a; b." sentence reads like a real letter and needs no verb conjugation.
    var coverLetterHighlights: String {
        (completedPositions.first?.filledBullets ?? [])
            .prefix(2)
            .map { bullet in
                var trimmed = bullet
                while trimmed.hasSuffix(".") { trimmed.removeLast() }
                return trimmed
            }
            .joined(separator: "; ")
    }

    /// Education formatted for the preview card's sidebar block.
    var educationSummary: String {
        completedEducation
            .map { $0.displayLines.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}

struct ResumeScoreBreakdown: Identifiable {
    let id = UUID()
    let title: String
    let percent: Int
    let icon: String
}

struct ImprovementSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct ResumeReview {
    var overallScore: Int
    var breakdown: [ResumeScoreBreakdown]
    var suggestions: [ImprovementSuggestion]
}

struct ApplicationKit {
    /// How well-written the resume is — spelling, structure, metrics, phrasing. Deliberately
    /// *not* named "job fit": it is computed without any knowledge of a job, and presenting it
    /// as a match percentage claimed something the app had never measured.
    var resumeScore: Int
    var suggestions: [ImprovementSuggestion]
}

/// One scored dimension of a job-fit comparison, with the counts behind it so the UI can show
/// why the number is what it is instead of asking the user to trust it.
struct JobFitComponent: Identifiable {
    let id = UUID()
    var title: String
    var percent: Int
    var detail: String
}

/// The result of comparing a resume against a specific job description.
///
/// Only ever produced when there *is* a job description — `AppState.jobFitAnalysis` is nil
/// otherwise, and the UI falls back to showing the resume score under its own name.
struct JobFitAnalysis {
    var overallScore: Int
    var components: [JobFitComponent]
    var matchedSkills: [String]
    var missingSkills: [String]
    var matchedKeywords: [String]
    var missingKeywords: [String]

    var summaryLabel: String {
        switch overallScore {
        case 85...: return "Strong match"
        case 70..<85: return "Good match"
        case 50..<70: return "Partial match"
        default: return "Weak match"
        }
    }
}

enum BuildSource {
    case upload
    case write
}

/// Which visual layout the generated resume uses — picked on the "Choose Template" screen.
enum ResumeTemplateStyle {
    case modernEdge
    case minimalPro
    case creativeBold
    case executiveSuite

    /// Hex color matching this style's accent as seen in `ResumeTemplateCard` — used to carry
    /// the chosen template's look into exported PDF/Word files, not just the in-app preview.
    var accentColorHex: String {
        switch self {
        case .modernEdge: return "4B39EF"
        case .minimalPro: return "000000"
        case .creativeBold: return "AF52DE"
        case .executiveSuite: return "595959"
        }
    }

    /// Executive Suite uses a serif typeface on-screen (`ResumeTemplateCard.executiveSuiteLayout`)
    /// — exported files mirror that so the export doesn't look identical to every other template.
    var usesSerifFont: Bool {
        self == .executiveSuite
    }

    /// Executive Suite centers the name/role/contact block on-screen; every other template is
    /// left-aligned throughout.
    var centersHeaderBlock: Bool {
        self == .executiveSuite
    }

    /// Which structural layout this template actually uses on-screen (`ResumeTemplateCard`) —
    /// a flat document with colored section headers can only ever approximate a template whose
    /// real identity is a colored sidebar or banner, so the exporters dispatch on this instead
    /// of just swapping colors/fonts within one fixed layout.
    enum ExportLayout {
        /// Modern Edge: a colored column (Contact + Skills, white text) down the left side,
        /// name/role/content in the remaining space to the right.
        case sidebar
        /// Creative Bold: a colored banner across the top (name/role/contact, white text),
        /// content flowing normally underneath.
        case banner
        /// Minimal Pro / Executive Suite: a single flowing column — already close to their
        /// actual plain/centered-serif on-screen look.
        case flowing
    }

    var exportLayout: ExportLayout {
        switch self {
        case .modernEdge: return .sidebar
        case .creativeBold: return .banner
        case .minimalPro, .executiveSuite: return .flowing
        }
    }
}
