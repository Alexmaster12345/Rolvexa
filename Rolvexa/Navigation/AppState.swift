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

    // MARK: - Library persistence

    /// Which saved resume this session is editing.
    ///
    /// Assigned the first time the work is saved, and carried from then on, so subsequent saves
    /// update that record rather than adding another copy to the library every time the app
    /// leaves the foreground.
    var currentResumeID: UUID?

    /// When the resume being edited was first saved. Preserved across saves so the library can
    /// show a creation date that doesn't move every time the user types.
    private var currentResumeCreatedAt: Date?

    /// The last score computed for the current resume, carried so a save can stamp it.
    private var currentScore: ResumeLibrary.ScoreStamp?

    /// The parts of this state worth surviving app termination.
    var currentResume: ResumeLibrary.SavedResume {
        let now = Date()
        return ResumeLibrary.SavedResume(
            id: currentResumeID ?? UUID(),
            experience: experience,
            jobTarget: jobTarget,
            templateStyle: selectedResumeTemplateStyle,
            createdAt: currentResumeCreatedAt ?? now,
            updatedAt: now,
            contentFingerprint: ResumeLibrary.fingerprint(
                experience: experience, jobTarget: jobTarget
            ),
            score: currentScore,
            // Captured here rather than rebuilt when sharing, because an uploaded resume's body
            // lives in `extractedResumeText` — which isn't persisted — and not in the
            // structured fields. Without this, sharing an upload from the library would hand
            // back a page with a name on it and nothing underneath.
            bodyText: resumeExportText()
        )
    }

    /// Persists the in-progress resume. Called when the app leaves the foreground rather than on
    /// every keystroke — the save is cheap but a resume is sensitive enough that writing it to
    /// disk on each character typed is more exposure than the feature needs.
    @discardableResult
    func saveCurrentResume() -> Bool {
        let resume = currentResume
        guard ResumeLibrary.save(resume) else { return false }
        currentResumeID = resume.id
        currentResumeCreatedAt = resume.createdAt
        return true
    }

    /// Loads a saved resume into this session, replacing whatever was being edited.
    @discardableResult
    func openResume(id: UUID) -> Bool {
        guard let resume = ResumeLibrary.load(id: id) else { return false }
        experience = resume.experience
        jobTarget = resume.jobTarget
        selectedResumeTemplateStyle = resume.templateStyle
        currentResumeID = resume.id
        currentResumeCreatedAt = resume.createdAt
        currentScore = resume.score
        clearDerivedResults()
        return true
    }

    /// Begins a new, empty resume. The library keeps whatever was already saved.
    func startNewResume() {
        experience = ExperienceInput()
        jobTarget = JobTarget()
        currentResumeID = nil
        currentResumeCreatedAt = nil
        currentScore = nil
        clearDerivedResults()
    }

    /// Records a freshly computed resume score against the content it was measured on.
    ///
    /// Stamped rather than stored bare so the library can stop showing it once the resume has
    /// been edited — see ``ResumeLibrary/ScoreStamp``.
    ///
    /// Writes immediately rather than waiting for the app to leave the foreground. Scoring only
    /// happens after the resume has real content, and a user who finishes a resume and then
    /// force-quits shouldn't find the library listing it without the number they just saw.
    func recordResumeScore(_ value: Int) {
        currentScore = ResumeLibrary.ScoreStamp(
            value: value,
            fingerprint: ResumeLibrary.fingerprint(experience: experience, jobTarget: jobTarget),
            computedAt: Date()
        )
        saveCurrentResume()
    }

    /// Deletes one saved resume. If it's the one open right now, the session is reset too —
    /// otherwise the next save would write it straight back.
    func deleteResume(id: UUID) {
        ResumeLibrary.delete(id: id)
        if currentResumeID == id { startNewResume() }
    }

    /// Forgets every saved resume — both in memory and on disk.
    func deleteAllResumes() {
        ResumeLibrary.deleteAll()
        startNewResume()
    }

    /// Drops everything derived from the previous resume. An upload's extracted text, review and
    /// generated kit all describe a specific document; leaving them in place while swapping the
    /// resume underneath is how a score from one resume ends up displayed next to another.
    private func clearDerivedResults() {
        uploadedFileName = nil
        extractedResumeText = nil
        extractedResumeDisplayText = nil
        extractedEmail = nil
        extractedPhone = nil
        extractedLocation = nil
        extractedEducation = nil
        extractedSummary = nil
        extractedCompany = nil
        extractedLinks = []
        uploadedResumeFileData = nil
        uploadedResumeFileExtension = nil
        keepOriginalUploadedLayout = false
        resumeTextWasManuallyFixed = false
        resumeReview = nil
        applicationKit = nil
        aiGeneratedSummary = nil
        aiGeneratedCoverLetterBody = nil
        aiReviewedThisSession = false
        suggestedJobTitles = []
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
