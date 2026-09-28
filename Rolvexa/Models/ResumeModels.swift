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

struct ExperienceInput {
    var fullName: String = ""
    var currentRole: String = ""
    var yearsOfExperience: String = "5–7 years"
    var skills: [String] = ["Product Design", "Figma", "User Research"]
    var email: String = ""
    var phone: String = ""
    var location: String = ""
    var education: String = ""
    var workHistorySummary: String = ""
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
    var jobFitScore: Int
    var suggestions: [ImprovementSuggestion]
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
