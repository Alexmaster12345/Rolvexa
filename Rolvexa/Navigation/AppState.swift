import Foundation
import Observation

@Observable
final class AppState {
    var buildSource: BuildSource = .write

    var uploadedFileName: String?
    var extractedResumeText: String?
    var extractedEmail: String?
    var extractedPhone: String?
    var extractedLocation: String?
    var extractedEducation: String?
    var extractedSummary: String?
    /// Company from the first entry under the resume's "Experience" section — used as a fallback
    /// display value (e.g. on "Review & Send") when no job target company has been entered yet.
    var extractedCompany: String?
    var extractedResumeDisplayText: String?
    var keepOriginalUploadedLayout = false
    var selectedResumeTemplateStyle: ResumeTemplateStyle = .modernEdge
    var uploadedResumeFileData: Data?
    var uploadedResumeFileExtension: String?
    var resumeReview: ResumeReview?
    /// True once "Fix It For Me" has edited `extractedResumeText` — from then on the original
    /// uploaded file's raw bytes no longer match the resume's actual current content, so "keep
    /// original layout" downloads must stop using them and fall back to a regenerated export of
    /// the (now fixed) text instead.
    var resumeTextWasManuallyFixed = false

    var jobTarget = JobTarget()
    var experience = ExperienceInput()

    var applicationKit: ApplicationKit?

    /// Set only when the on-device AI agent (ResumeIntelligenceAgent) successfully generated
    /// real, tailored copy. Nil means "fall back to the deterministic template" — either the
    /// agent isn't available on this device, or the call failed.
    var aiGeneratedSummary: String?
    var aiGeneratedCoverLetterBody: String?
    var aiReviewedThisSession = false

    /// Other job titles the on-device AI thinks this candidate's background fits well, beyond
    /// the one target role. Empty means "not generated" — the UI hides the section rather than
    /// showing a fallback guess, since a wrong guess here is worse than no suggestion.
    var suggestedJobTitles: [String] = []

    /// True while the "Reach a 100% score" action is running the on-device AI rewrite.
    var isImprovingResume = false
}
