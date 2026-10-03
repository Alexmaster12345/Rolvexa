import Foundation
import Testing
@testable import Rolvexa

/// Draft persistence. These run against the real file on disk rather than a mock, because the
/// things most worth asserting here — that it round-trips, that it's protected, that it doesn't
/// leave a file behind when there's nothing to save — are properties of the filesystem call,
/// not of the encoding.
@MainActor
struct ResumeDraftStoreTests {
    /// Each test starts and ends with no draft on disk, so one leaving state behind can't make
    /// another pass or fail spuriously.
    private func withCleanStore(_ body: () throws -> Void) rethrows {
        ResumeDraftStore.clear()
        defer { ResumeDraftStore.clear() }
        try body()
    }

    private func filledDraft() -> ResumeDraftStore.Draft {
        var experience = ExperienceInput()
        experience.fullName = "Jane Doe"
        experience.currentRole = "Operations Manager"
        experience.email = "jane.doe@example.com"
        experience.skills = ["Process Design", "Reporting"]

        var job = WorkExperienceEntry()
        job.title = "Operations Manager"
        job.company = "Acme Corporation"
        job.startDate = "2017"
        job.isCurrent = true
        job.bullets = ["Cut supplier onboarding time from 14 days to 5"]
        experience.positions = [job]

        var school = EducationEntry()
        school.degree = "BSc Business Administration"
        school.school = "State University"
        experience.educationEntries = [school]

        var target = JobTarget()
        target.title = "Senior Operations Manager"
        target.company = "Initech"

        return ResumeDraftStore.Draft(
            experience: experience, jobTarget: target,
            templateStyle: .executiveSuite, savedAt: Date()
        )
    }

    // MARK: - Round trip

    @Test("A saved draft comes back with every field intact")
    func draftRoundTrips() throws {
        try withCleanStore {
            let original = filledDraft()
            #expect(ResumeDraftStore.save(original))

            let loaded = try #require(ResumeDraftStore.load())
            #expect(loaded.experience.fullName == "Jane Doe")
            #expect(loaded.experience.email == "jane.doe@example.com")
            #expect(loaded.experience.skills == ["Process Design", "Reporting"])
            #expect(loaded.experience.positions.first?.company == "Acme Corporation")
            #expect(loaded.experience.positions.first?.isCurrent == true)
            #expect(loaded.experience.educationEntries.first?.school == "State University")
            #expect(loaded.jobTarget.title == "Senior Operations Manager")
            #expect(loaded.templateStyle == .executiveSuite)
        }
    }

    @Test("A photo survives the round trip")
    func photoRoundTrips() throws {
        try withCleanStore {
            var draft = filledDraft()
            let bytes = Data((0..<256).map { UInt8($0 % 251) })
            draft.experience.photoData = bytes
            #expect(ResumeDraftStore.save(draft))
            let loaded = try #require(ResumeDraftStore.load())
            #expect(loaded.experience.photoData == bytes)
        }
    }

    // MARK: - Not saving nothing

    @Test("An untouched form leaves no file on disk")
    func emptyDraftIsNotPersisted() {
        withCleanStore {
            let empty = ResumeDraftStore.Draft(
                experience: ExperienceInput(), jobTarget: JobTarget(),
                templateStyle: .modernEdge, savedAt: Date()
            )
            #expect(!ResumeDraftStore.isWorthSaving(empty))
            #expect(!ResumeDraftStore.save(empty))
            #expect(!ResumeDraftStore.hasDraft)
        }
    }

    @Test("Whitespace alone doesn't count as progress")
    func whitespaceOnlyIsNotWorthSaving() {
        var experience = ExperienceInput()
        experience.fullName = "   "
        experience.summary = "\n\t "
        let draft = ResumeDraftStore.Draft(
            experience: experience, jobTarget: JobTarget(),
            templateStyle: .modernEdge, savedAt: Date()
        )
        #expect(!ResumeDraftStore.isWorthSaving(draft))
    }

    @Test("Saving an emptied form deletes the file rather than leaving a stale one")
    func savingEmptyClearsPreviousDraft() {
        withCleanStore {
            #expect(ResumeDraftStore.save(filledDraft()))
            #expect(ResumeDraftStore.hasDraft)

            let empty = ResumeDraftStore.Draft(
                experience: ExperienceInput(), jobTarget: JobTarget(),
                templateStyle: .modernEdge, savedAt: Date()
            )
            _ = ResumeDraftStore.save(empty)
            #expect(!ResumeDraftStore.hasDraft, "an emptied form must not leave the old resume behind")
        }
    }

    @Test("A single filled field is enough to be worth saving", arguments: [
        "name", "skills", "photo", "job", "target"
    ])
    func anyRealProgressIsSaved(kind: String) {
        var experience = ExperienceInput()
        var target = JobTarget()
        switch kind {
        case "name": experience.fullName = "Jane Doe"
        case "skills": experience.skills = ["Reporting"]
        case "photo": experience.photoData = Data([0x01])
        case "job":
            var job = WorkExperienceEntry()
            job.title = "Analyst"; job.company = "Acme"; job.bullets = ["Did the work"]
            experience.positions = [job]
        default: target.company = "Initech"
        }
        let draft = ResumeDraftStore.Draft(
            experience: experience, jobTarget: target,
            templateStyle: .modernEdge, savedAt: Date()
        )
        #expect(ResumeDraftStore.isWorthSaving(draft))
    }

    // MARK: - Protection

    @Test("The draft is written encrypted-at-rest and excluded from backups")
    func draftIsProtectedOnDisk() throws {
        try withCleanStore {
            #expect(ResumeDraftStore.save(filledDraft()))

            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
            let url = directory.appendingPathComponent("resume-draft.json")

            // Application Support, not Documents — a resume shouldn't be browsable in the
            // Files app.
            #expect(!url.path.contains("/Documents/"))

            // Backup exclusion is honoured everywhere, so it's asserted unconditionally.
            let excluded = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
            #expect(excluded == true, "a resume shouldn't propagate off-device through a backup")

            // Data protection is a device feature; the simulator accepts the write option but
            // reports no protection key back. Assert it where the platform implements it rather
            // than writing a test that can only fail in CI.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let protection = attributes[.protectionKey] as? FileProtectionType {
                #expect(
                    protection == .complete,
                    "a resume on disk must be unreadable while the device is locked"
                )
            }
        }
    }

    // MARK: - Corruption

    @Test("An unreadable draft is discarded instead of breaking launch")
    func corruptDraftIsDiscarded() throws {
        try withCleanStore {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let url = directory.appendingPathComponent("resume-draft.json")
            try Data("this is not json".utf8).write(to: url)

            #expect(ResumeDraftStore.load() == nil)
            #expect(!ResumeDraftStore.hasDraft, "the unreadable file should have been cleaned up")
        }
    }

    // MARK: - AppState integration

    @Test("A restored draft repopulates the form")
    func appStateRestoresADraft() {
        withCleanStore {
            let source = AppState()
            source.experience.fullName = "Jane Doe"
            source.experience.skills = ["Reporting"]
            source.jobTarget.company = "Initech"
            source.selectedResumeTemplateStyle = .creativeBold
            source.saveDraft()

            let fresh = AppState()
            #expect(fresh.restoreDraftIfAvailable())
            #expect(fresh.experience.fullName == "Jane Doe")
            #expect(fresh.jobTarget.company == "Initech")
            #expect(fresh.selectedResumeTemplateStyle == .creativeBold)
        }
    }

    @Test("Restoring never overwrites work already started this session")
    func restoreDoesNotClobberInProgressWork() {
        withCleanStore {
            let source = AppState()
            source.experience.fullName = "Jane Doe"
            source.saveDraft()

            let inProgress = AppState()
            inProgress.experience.fullName = "Someone Else"
            #expect(!inProgress.restoreDraftIfAvailable())
            #expect(inProgress.experience.fullName == "Someone Else")
        }
    }

    @Test("Discarding wipes the draft from memory and disk")
    func discardClearsEverything() {
        withCleanStore {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            state.saveDraft()
            #expect(ResumeDraftStore.hasDraft)

            state.discardDraft()
            #expect(!ResumeDraftStore.hasDraft)
            #expect(state.experience.fullName.isEmpty)
        }
    }
}
