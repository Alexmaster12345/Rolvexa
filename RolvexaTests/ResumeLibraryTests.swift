import Foundation
import PDFKit
import Testing
@testable import Rolvexa

/// Library persistence. These run against real files on disk rather than a mock, because the
/// things most worth asserting here — that records round-trip, that they're protected, that an
/// empty one leaves nothing behind, that two resumes don't overwrite each other — are properties
/// of the filesystem calls, not of the encoding.
@MainActor
struct ResumeLibraryTests {
    /// Each test starts and ends with an empty library, so one leaving state behind can't make
    /// another pass or fail spuriously.
    private func withCleanLibrary(_ body: () throws -> Void) rethrows {
        ResumeLibrary.deleteAll()
        defer { ResumeLibrary.deleteAll() }
        try body()
    }

    private func filledResume(
        role: String = "Operations Manager",
        company: String = "Initech"
    ) -> ResumeLibrary.SavedResume {
        var experience = ExperienceInput()
        experience.fullName = "Jane Doe"
        experience.currentRole = role
        experience.email = "jane.doe@example.com"
        experience.skills = ["Process Design", "Reporting"]

        var job = WorkExperienceEntry()
        job.title = role
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
        target.title = "Senior \(role)"
        target.company = company

        return ResumeLibrary.SavedResume(
            experience: experience,
            jobTarget: target,
            templateStyle: .executiveSuite,
            createdAt: Date(),
            updatedAt: Date(),
            contentFingerprint: ResumeLibrary.fingerprint(
                experience: experience, jobTarget: target
            )
        )
    }

    private func emptyResume() -> ResumeLibrary.SavedResume {
        ResumeLibrary.SavedResume(
            experience: ExperienceInput(),
            jobTarget: JobTarget(),
            templateStyle: .modernEdge,
            createdAt: Date(),
            updatedAt: Date(),
            contentFingerprint: ""
        )
    }

    // MARK: - Round trip

    @Test("A saved resume comes back with every field intact")
    func resumeRoundTrips() throws {
        try withCleanLibrary {
            let original = filledResume()
            #expect(ResumeLibrary.save(original))

            let loaded = try #require(ResumeLibrary.load(id: original.id))
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
        try withCleanLibrary {
            var resume = filledResume()
            let bytes = Data((0..<256).map { UInt8($0 % 251) })
            resume.experience.photoData = bytes
            #expect(ResumeLibrary.save(resume))
            let loaded = try #require(ResumeLibrary.load(id: resume.id))
            #expect(loaded.experience.photoData == bytes)
        }
    }

    // MARK: - Many resumes

    @Test("Saving a second resume doesn't overwrite the first")
    func resumesAreIndependent() throws {
        try withCleanLibrary {
            let first = filledResume(role: "Operations Manager", company: "Initech")
            let second = filledResume(role: "Product Designer", company: "Globex")
            #expect(ResumeLibrary.save(first))
            #expect(ResumeLibrary.save(second))

            #expect(ResumeLibrary.count == 2)
            let loadedFirst = try #require(ResumeLibrary.load(id: first.id))
            let loadedSecond = try #require(ResumeLibrary.load(id: second.id))
            #expect(loadedFirst.jobTarget.company == "Initech")
            #expect(loadedSecond.jobTarget.company == "Globex")
        }
    }

    @Test("Re-saving the same resume updates it in place")
    func resavingDoesNotDuplicate() throws {
        try withCleanLibrary {
            var resume = filledResume()
            #expect(ResumeLibrary.save(resume))
            resume.experience.fullName = "Jane Q. Doe"
            #expect(ResumeLibrary.save(resume))

            #expect(ResumeLibrary.count == 1)
            let loaded = try #require(ResumeLibrary.load(id: resume.id))
            #expect(loaded.experience.fullName == "Jane Q. Doe")
        }
    }

    @Test("The list is newest-first")
    func summariesAreSortedByRecency() {
        withCleanLibrary {
            let older = filledResume(role: "Operations Manager")
            let newer = filledResume(role: "Product Designer")
            ResumeLibrary.save(older, modifiedAt: Date().addingTimeInterval(-86_400))
            ResumeLibrary.save(newer, modifiedAt: Date())

            #expect(ResumeLibrary.summaries().map(\.id) == [newer.id, older.id])
        }
    }

    @Test("Deleting one resume leaves the others alone")
    func deletingOneIsTargeted() {
        withCleanLibrary {
            let kept = filledResume(role: "Operations Manager")
            let removed = filledResume(role: "Product Designer")
            ResumeLibrary.save(kept)
            ResumeLibrary.save(removed)

            ResumeLibrary.delete(id: removed.id)
            #expect(ResumeLibrary.summaries().map(\.id) == [kept.id])
        }
    }

    // MARK: - Summaries

    @Test("A summary names the role and employer rather than the file")
    func summaryDescribesTheResume() throws {
        try withCleanLibrary {
            let resume = filledResume(role: "Operations Manager", company: "Initech")
            ResumeLibrary.save(resume)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.title == "Senior Operations Manager")
            #expect(summary.subtitle == "Initech")
        }
    }

    @Test("A resume saved before any role was entered isn't given an invented title")
    func untitledResumeSaysSo() throws {
        try withCleanLibrary {
            var experience = ExperienceInput()
            experience.email = "jane.doe@example.com"
            let resume = ResumeLibrary.SavedResume(
                experience: experience,
                jobTarget: JobTarget(),
                templateStyle: .modernEdge,
                createdAt: Date(),
                updatedAt: Date(),
                contentFingerprint: ResumeLibrary.fingerprint(
                    experience: experience, jobTarget: JobTarget()
                )
            )
            ResumeLibrary.save(resume)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.title == "Untitled resume")
        }
    }

    @Test("Search matches role, employer and skills", arguments: [
        "operations", "initech", "reporting", "OPERATIONS MANAGER", "jane"
    ])
    func searchMatchesTheObviousThings(query: String) throws {
        try withCleanLibrary {
            ResumeLibrary.save(filledResume(role: "Operations Manager", company: "Initech"))
            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.matches(query))
        }
    }

    @Test("Search excludes resumes that don't match")
    func searchExcludesNonMatches() throws {
        try withCleanLibrary {
            ResumeLibrary.save(filledResume(role: "Operations Manager", company: "Initech"))
            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(!summary.matches("radiologist"))
            #expect(summary.matches("   "), "a blank query shows everything")
        }
    }

    // MARK: - Scores

    @Test("A score is shown while it still describes the resume")
    func currentScoreIsSurfaced() throws {
        try withCleanLibrary {
            var resume = filledResume()
            resume.score = ResumeLibrary.ScoreStamp(
                value: 88, fingerprint: resume.contentFingerprint, computedAt: Date()
            )
            ResumeLibrary.save(resume)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.score == 88)
        }
    }

    @Test("A score computed before an edit is not shown afterwards")
    func staleScoreIsWithheld() throws {
        try withCleanLibrary {
            var resume = filledResume()
            resume.score = ResumeLibrary.ScoreStamp(
                value: 88, fingerprint: resume.contentFingerprint, computedAt: Date()
            )
            ResumeLibrary.save(resume)

            // Rewrite a bullet. The number measured a document that no longer exists.
            var edited = try #require(ResumeLibrary.load(id: resume.id))
            edited.experience.positions[0].bullets = ["Did some things"]
            ResumeLibrary.save(edited)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.score == nil, "a score must not outlive the text it was measured on")
        }
    }

    @Test("Changes that can't move the score don't throw it away", arguments: [
        "phone", "linkedIn", "photo"
    ])
    func irrelevantEditsKeepTheScore(field: String) throws {
        try withCleanLibrary {
            var resume = filledResume()
            resume.score = ResumeLibrary.ScoreStamp(
                value: 88, fingerprint: resume.contentFingerprint, computedAt: Date()
            )
            ResumeLibrary.save(resume)

            var edited = try #require(ResumeLibrary.load(id: resume.id))
            switch field {
            case "phone": edited.experience.phone = "555-010-0100"
            case "linkedIn": edited.experience.linkedIn = "linkedin.com/in/your-name"
            default: edited.experience.photoData = Data([0x01, 0x02])
            }
            ResumeLibrary.save(edited)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.score == 88)
        }
    }

    @Test("The same content always fingerprints the same way")
    func fingerprintIsStable() {
        let resume = filledResume()
        #expect(
            ResumeLibrary.fingerprint(experience: resume.experience, jobTarget: resume.jobTarget)
                == ResumeLibrary.fingerprint(
                    experience: resume.experience, jobTarget: resume.jobTarget
                )
        )
    }

    // MARK: - Not saving nothing

    @Test("An untouched form leaves no file on disk")
    func emptyResumeIsNotPersisted() {
        withCleanLibrary {
            let empty = emptyResume()
            #expect(!ResumeLibrary.isWorthSaving(empty))
            #expect(!ResumeLibrary.save(empty))
            #expect(ResumeLibrary.isEmpty)
        }
    }

    @Test("Whitespace alone doesn't count as progress")
    func whitespaceOnlyIsNotWorthSaving() {
        var resume = emptyResume()
        resume.experience.fullName = "   "
        resume.experience.summary = "\n\t "
        #expect(!ResumeLibrary.isWorthSaving(resume))
    }

    @Test("Saving an emptied form deletes that resume rather than leaving a stale one")
    func savingEmptyRemovesTheRecord() {
        withCleanLibrary {
            var resume = filledResume()
            #expect(ResumeLibrary.save(resume))
            #expect(ResumeLibrary.count == 1)

            resume.experience = ExperienceInput()
            resume.jobTarget = JobTarget()
            _ = ResumeLibrary.save(resume)
            #expect(ResumeLibrary.isEmpty, "an emptied form must not leave the old resume behind")
        }
    }

    @Test("A single filled field is enough to be worth saving", arguments: [
        "name", "skills", "photo", "job", "target"
    ])
    func anyRealProgressIsSaved(kind: String) {
        var resume = emptyResume()
        switch kind {
        case "name": resume.experience.fullName = "Jane Doe"
        case "skills": resume.experience.skills = ["Reporting"]
        case "photo": resume.experience.photoData = Data([0x01])
        case "job":
            var job = WorkExperienceEntry()
            job.title = "Analyst"; job.company = "Acme"; job.bullets = ["Did the work"]
            resume.experience.positions = [job]
        default: resume.jobTarget.company = "Initech"
        }
        #expect(ResumeLibrary.isWorthSaving(resume))
    }

    // MARK: - Protection

    @Test("Resumes are written encrypted-at-rest and excluded from backups")
    func storageIsProtectedOnDisk() throws {
        try withCleanLibrary {
            let resume = filledResume()
            #expect(ResumeLibrary.save(resume))

            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
            let folder = directory.appendingPathComponent("Resumes", isDirectory: true)
            let url = folder.appendingPathComponent("\(resume.id.uuidString).json")

            // Application Support, not Documents — a resume shouldn't be browsable in the
            // Files app.
            #expect(!url.path.contains("/Documents/"))
            #expect(FileManager.default.fileExists(atPath: url.path))

            // Backup exclusion is honoured everywhere, so it's asserted unconditionally. It's
            // set on the folder, which covers everything written into it.
            let excluded = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup
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

    @Test("An unreadable record is skipped instead of hiding the whole library")
    func corruptRecordIsIsolated() throws {
        try withCleanLibrary {
            let good = filledResume()
            #expect(ResumeLibrary.save(good))

            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let folder = directory.appendingPathComponent("Resumes", isDirectory: true)
            let corrupt = folder.appendingPathComponent("\(UUID().uuidString).json")
            try Data("this is not json".utf8).write(to: corrupt)

            #expect(
                ResumeLibrary.summaries().map(\.id) == [good.id],
                "one bad file must not take the readable resumes down with it"
            )
        }
    }

    // MARK: - Migration

    @Test("A draft written by an earlier build is carried into the library")
    func legacyDraftIsMigrated() throws {
        try withCleanLibrary {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let legacy = directory.appendingPathComponent("resume-draft.json")
            defer { try? FileManager.default.removeItem(at: legacy) }

            // The exact shape earlier builds wrote.
            let json = """
            {"experience":{"fullName":"Jane Doe","currentRole":"Operations Manager",\
            "yearsOfExperience":"5–7 years","skills":["Reporting"],"email":"","phone":"",\
            "location":"","linkedIn":"","portfolio":"","summary":"","positions":[],\
            "educationEntries":[]},\
            "jobTarget":{"descriptionText":"","title":"","company":"Initech","level":"Senior"},\
            "templateStyle":"creativeBold","savedAt":760000000}
            """
            try Data(json.utf8).write(to: legacy)

            ResumeLibrary.migrateLegacyDraftIfNeeded()

            let summaries = ResumeLibrary.summaries()
            #expect(summaries.count == 1)
            #expect(summaries.first?.title == "Operations Manager")
            // The draft's own timestamp, not the moment the update was installed.
            let expected = Date(timeIntervalSinceReferenceDate: 760_000_000)
            #expect(
                abs(try #require(summaries.first).updatedAt.timeIntervalSince(expected)) < 1,
                "migration must preserve when the user last edited, not stamp it as just now"
            )
            #expect(
                !FileManager.default.fileExists(atPath: legacy.path),
                "the old file should be gone, so the next launch doesn't migrate it twice"
            )
        }
    }

    @Test("Migration on a device that never had a draft does nothing")
    func migrationIsANoOpWithoutALegacyFile() {
        withCleanLibrary {
            ResumeLibrary.migrateLegacyDraftIfNeeded()
            #expect(ResumeLibrary.isEmpty)
        }
    }

    // MARK: - Sharing one resume

    @Test("A saved resume renders a real file to share", arguments: [ExportFormat.pdf, .word])
    func sharedFileIsARealDocument(format: ExportFormat) throws {
        try withCleanLibrary {
            let resume = filledResume()
            #expect(ResumeLibrary.save(resume))

            let url = try #require(ResumeLibrary.shareableFile(for: resume.id, format: format))
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(url.pathExtension == format.fileExtension)
            let data = try Data(contentsOf: url)
            #expect(data.count > 1_000, "a resume should not render to a near-empty file")
            // Signature check rather than a size heuristic alone: "%PDF" or a zip local header.
            let magic = Array(data.prefix(4))
            #expect(
                format == .pdf
                    ? magic == Array("%PDF".utf8)
                    : magic == [0x50, 0x4B, 0x03, 0x04]
            )
        }
    }

    @Test("The shared file carries the candidate's own content, not a template")
    func sharedPDFContainsTheResume() throws {
        try withCleanLibrary {
            let resume = filledResume()
            #expect(ResumeLibrary.save(resume))

            let url = try #require(ResumeLibrary.shareableFile(for: resume.id, format: .pdf))
            defer { try? FileManager.default.removeItem(at: url) }

            let document = try #require(PDFDocument(url: url))
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")

            #expect(text.contains("Jane Doe"))
            #expect(text.contains("Acme Corporation"))
            #expect(text.contains("Cut supplier onboarding time from 14 days to 5"))
        }
    }

    @Test("An uploaded resume's body survives into the shared file")
    func uploadBodyIsSharedRatherThanRebuiltFromEmptyFields() throws {
        try withCleanLibrary {
            // What the upload flow actually leaves behind: a name, a role and skills in the
            // structured fields, and the entire employment history only in the extracted text.
            var experience = ExperienceInput()
            experience.fullName = "Jane Doe"
            experience.currentRole = "Facility Property Manager"
            experience.skills = ["Vendor Management"]

            var resume = filledResume()
            resume.experience = experience
            resume.bodyText = """
            Jane Doe
            Facility Property Manager

            PROFESSIONAL EXPERIENCE
            Facility Property Manager | 2017 – Present
            Acme Corporation, Anytown USA
            • Oversaw 12 commercial properties
            """
            #expect(ResumeLibrary.save(resume))

            let url = try #require(ResumeLibrary.shareableFile(for: resume.id, format: .pdf))
            defer { try? FileManager.default.removeItem(at: url) }

            let document = try #require(PDFDocument(url: url))
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")

            #expect(
                text.contains("Oversaw 12 commercial properties"),
                "rebuilding from the structured fields alone would have lost the whole history"
            )
        }
    }

    @Test("A resume with nothing but a name offers nothing to share")
    func emptyResumeIsNotShareable() throws {
        try withCleanLibrary {
            var experience = ExperienceInput()
            experience.fullName = "Jane Doe"
            experience.currentRole = "Operations Manager"
            let resume = ResumeLibrary.SavedResume(
                experience: experience,
                jobTarget: JobTarget(),
                templateStyle: .modernEdge,
                createdAt: Date(),
                updatedAt: Date(),
                contentFingerprint: ResumeLibrary.fingerprint(
                    experience: experience, jobTarget: JobTarget()
                )
            )
            #expect(ResumeLibrary.save(resume))

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(!summary.canShare, "an empty page must not be offered as a resume")
            #expect(ResumeLibrary.shareableFile(for: resume.id, format: .pdf) == nil)
        }
    }

    @Test("A resume with real content is offered for sharing")
    func filledResumeIsShareable() throws {
        try withCleanLibrary {
            #expect(ResumeLibrary.save(filledResume()))
            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.canShare)
        }
    }

    @Test("Sharing a resume that no longer exists returns nothing rather than an empty file")
    func sharingADeletedResumeIsNil() {
        withCleanLibrary {
            #expect(ResumeLibrary.shareableFile(for: UUID(), format: .pdf) == nil)
        }
    }

    @Test("The shared file is named after the person and the role")
    func shareFilenameIsRecognisable() {
        let resume = filledResume(role: "Operations Manager")
        #expect(ResumeLibrary.shareFilename(for: resume) == "Jane-Doe-Senior-Operations-Manager")
    }

    @Test("A name in a non-Latin script survives the filename, rather than becoming hyphens")
    func shareFilenameKeepsNonLatinNames() {
        var resume = filledResume()
        resume.experience.fullName = "ישראל ישראלי"
        resume.jobTarget.title = ""
        resume.experience.currentRole = ""
        #expect(ResumeLibrary.shareFilename(for: resume) == "ישראל-ישראלי")
    }

    @Test("A resume with no name still gets a usable filename")
    func shareFilenameFallsBack() {
        var resume = filledResume()
        resume.experience.fullName = ""
        resume.experience.currentRole = ""
        resume.jobTarget.title = ""
        #expect(ResumeLibrary.shareFilename(for: resume) == "Resume")
    }

    // MARK: - Export

    @Test("Export writes readable JSON covering every saved resume")
    func exportCoversTheWholeLibrary() throws {
        try withCleanLibrary {
            ResumeLibrary.save(filledResume(role: "Operations Manager"))
            ResumeLibrary.save(filledResume(role: "Product Designer"))

            let url = try #require(ResumeLibrary.exportForSharing())
            defer { try? FileManager.default.removeItem(at: url) }

            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("Operations Manager"))
            #expect(text.contains("Product Designer"))
            // ISO-8601 rather than a float, so the file is readable by the person it's about.
            #expect(text.contains("T") && text.contains("Z"))
        }
    }

    @Test("Export with nothing stored returns nothing rather than an empty file")
    func exportWithoutDataIsNil() {
        withCleanLibrary {
            #expect(ResumeLibrary.exportForSharing() == nil)
        }
    }

    // MARK: - AppState integration

    @Test("Opening a saved resume repopulates the form")
    func appStateOpensAResume() throws {
        try withCleanLibrary {
            let source = AppState()
            source.experience.fullName = "Jane Doe"
            source.experience.skills = ["Reporting"]
            source.jobTarget.company = "Initech"
            source.selectedResumeTemplateStyle = .creativeBold
            #expect(source.saveCurrentResume())
            let id = try #require(source.currentResumeID)

            let fresh = AppState()
            #expect(fresh.openResume(id: id))
            #expect(fresh.experience.fullName == "Jane Doe")
            #expect(fresh.jobTarget.company == "Initech")
            #expect(fresh.selectedResumeTemplateStyle == .creativeBold)
        }
    }

    @Test("Repeated saves in one session update one record rather than piling up copies")
    func savingTwiceKeepsOneRecord() {
        withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            #expect(state.saveCurrentResume())
            state.experience.currentRole = "Operations Manager"
            #expect(state.saveCurrentResume())

            #expect(ResumeLibrary.count == 1)
        }
    }

    @Test("Starting a new resume keeps the old one in the library")
    func startingNewPreservesTheOld() {
        withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            #expect(state.saveCurrentResume())

            state.startNewResume()
            #expect(state.experience.fullName.isEmpty)
            #expect(state.currentResumeID == nil)
            #expect(ResumeLibrary.count == 1, "a new resume must not replace the saved one")
        }
    }

    @Test("Opening a resume drops the previous one's derived results")
    func openingClearsStaleDerivedState() throws {
        try withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            #expect(state.saveCurrentResume())
            let id = try #require(state.currentResumeID)

            // Results belonging to some other document.
            state.extractedResumeText = "text from a different upload"
            state.applicationKit = ApplicationKit(resumeScore: 99, suggestions: [])
            state.resumeReview = ResumeReview(overallScore: 99, breakdown: [], suggestions: [])

            #expect(state.openResume(id: id))
            #expect(state.extractedResumeText == nil)
            #expect(state.applicationKit == nil, "a score from another resume must not follow this one")
            #expect(state.resumeReview == nil)
        }
    }

    @Test("A recorded score is persisted immediately, not only on backgrounding")
    func recordedScoreIsWrittenThrough() throws {
        try withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            state.experience.currentRole = "Operations Manager"
            state.recordResumeScore(81)

            let summary = try #require(ResumeLibrary.summaries().first)
            #expect(summary.score == 81)
        }
    }

    @Test("Deleting the open resume resets the session so it isn't written back")
    func deletingTheOpenResumeResetsState() throws {
        try withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            #expect(state.saveCurrentResume())
            let id = try #require(state.currentResumeID)

            state.deleteResume(id: id)
            #expect(ResumeLibrary.isEmpty)
            #expect(state.experience.fullName.isEmpty)

            // The bug this guards against: a stale id left behind would let the next save
            // recreate the record the user just deleted.
            _ = state.saveCurrentResume()
            #expect(ResumeLibrary.isEmpty)
        }
    }

    @Test("Deleting everything wipes memory and disk")
    func deleteAllClearsEverything() {
        withCleanLibrary {
            let state = AppState()
            state.experience.fullName = "Jane Doe"
            #expect(state.saveCurrentResume())

            state.deleteAllResumes()
            #expect(ResumeLibrary.isEmpty)
            #expect(state.experience.fullName.isEmpty)
        }
    }
}
