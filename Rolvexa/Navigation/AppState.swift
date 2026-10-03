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
    /// Profile/portfolio URLs (LinkedIn, GitHub, …) pulled out of an uploaded resume. Rendered
    /// with the contact details rather than left loose in the body.
    var extractedLinks: [String] = []
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

    /// How the resume measures up against the pasted job description, or nil when none was
    /// given. Computed on demand rather than cached: it's pure string work, and a stale match
    /// percentage surviving an edit to either the resume or the posting would be worse than
    /// recomputing it.
    var jobFitAnalysis: JobFitAnalysis? {
        JobFitAnalyzer.analyze(
            jobDescription: jobTarget.descriptionText,
            resumeText: resumeExportText(),
            resumeSkills: experience.skills
        )
    }

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

    /// Whether the upload was a photo/screenshot rather than a document. Images reach the app as
    /// OCR'd text only — there's no document structure to preserve.
    var uploadedIsImage: Bool {
        guard let uploadedResumeFileExtension else { return false }
        return ResumeTextExtraction.isImageFileExtension(uploadedResumeFileExtension)
    }

    /// Whether "keep the original layout" is even a meaningful choice for this upload. It isn't
    /// for an image: the "original" is a photo, and handing someone back their own JPEG as the
    /// finished resume defeats the point of uploading it. Image uploads always go through a
    /// template, which is the whole reason to convert them to text in the first place.
    var canKeepOriginalUploadedLayout: Bool {
        buildSource == .upload && uploadedResumeFileData != nil && !uploadedIsImage
    }

    /// The effective answer to "should the preview and downloads use the original file's bytes?"
    /// — the user's choice ANDed with whether that choice is even possible. Consumers should read
    /// this rather than `keepOriginalUploadedLayout` directly, so a value left over from an
    /// earlier upload in the same session can't apply itself to an image.
    var isKeepingOriginalUploadedLayout: Bool {
        keepOriginalUploadedLayout && canKeepOriginalUploadedLayout
    }

    /// Replaces the uploaded resume's text and re-derives the body shown in the preview and
    /// exports.
    ///
    /// Both must move together. "Fix It For Me" used to assign the fixed *raw* text straight to
    /// `extractedResumeDisplayText`, which threw away the header-block de-duplication done at
    /// upload — the name, contact details and profile links all reappeared in the body, looking
    /// exactly like the original bug. Re-deriving keeps the two in step however the text changes.
    func updateExtractedResumeText(_ newText: String) {
        extractedResumeText = newText
        extractedResumeDisplayText = ResumeSectionKit.removingHeaderBlock(
            from: newText,
            name: experience.fullName,
            role: experience.currentRole,
            summary: extractedSummary ?? "",
            email: extractedEmail,
            phone: extractedPhone,
            location: extractedLocation
        )
    }
}
