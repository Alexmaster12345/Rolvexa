import Foundation
import CryptoKit

/// Every resume the user has saved, on disk.
///
/// This replaces the single-draft `ResumeDraftStore`. The app used to keep exactly one
/// in-progress resume, so tailoring a second one for a different role silently overwrote the
/// first. Each saved resume is now its own record with its own history.
///
/// Writing resumes to disk in an app whose whole claim is privacy deserves care, so:
///
/// - They live in Application Support, not Documents, so they aren't exposed through the Files
///   app or iTunes file sharing.
/// - Each is written with `.completeFileProtection`, so iOS keeps it encrypted whenever the
///   device is locked and the key is unavailable even to this process.
/// - The whole folder is excluded from iCloud and iTunes backups — a resume shouldn't silently
///   propagate off the device through a backup when the app promises it won't leave.
/// - ``delete(id:)`` and ``deleteAll()`` remove the files outright.
///
/// One file per resume, rather than one file holding all of them: a save then rewrites only the
/// resume being edited, and a record corrupted by a half-finished write can't take the rest of
/// the library down with it.
enum ResumeLibrary {

    // MARK: - Stored shape

    /// One saved resume, as it exists on disk.
    ///
    /// Deliberately not the whole of `AppState`: the uploaded file's raw bytes, the derived
    /// review and the generated kit are all large, cheap to recompute, or both — persisting them
    /// would multiply the on-disk footprint of the most sensitive data for no benefit.
    struct SavedResume: Codable, Identifiable {
        var id: UUID = UUID()
        var experience: ExperienceInput
        var jobTarget: JobTarget
        var templateStyle: ResumeTemplateStyle
        var createdAt: Date
        var updatedAt: Date
        /// A digest of the scoring-relevant content, recomputed on every save. Stored rather
        /// than derived at read time so the list screen can tell a stale score from a current
        /// one with a string comparison instead of decoding and re-digesting every record.
        var contentFingerprint: String
        /// The last score this resume was given, if it has ever been scored.
        var score: ScoreStamp?
        /// The assembled resume text, exactly as the preview and the exporters consume it.
        ///
        /// Stored rather than always re-derived because an *uploaded* resume's body doesn't live
        /// in the structured fields at all — the upload flow fills in a name, a role and skills
        /// and leaves the employment history in extracted text. Rebuilding from structure alone
        /// would hand an upload user a page with their name on it and nothing underneath.
        ///
        /// Nil for records written before this field existed, and for ones built directly in
        /// tests; ``shareableBody()`` falls back to the structured assembly in that case.
        var bodyText: String?

        /// Whether ``score`` still describes what's in this resume now.
        var hasCurrentScore: Bool { score?.fingerprint == contentFingerprint }

        /// The text to render when sharing this resume, or nil when there isn't enough here to
        /// make a document worth sending.
        func shareableBody() -> String? {
            if let bodyText, ResumeExportText.hasBodyWorthSharing(bodyText) {
                return bodyText
            }
            guard ResumeExportText.hasShareableContent(experience: experience) else { return nil }
            return ResumeExportText.fromStructuredInput(
                experience: experience, jobTarget: jobTarget
            )
        }
    }

    /// A score, stamped with the content it was measured on.
    ///
    /// A number alone would go stale the moment a bullet changed, and a resume list showing
    /// "92%" next to text that has since been rewritten is exactly the kind of confident-but-
    /// wrong claim this app keeps having to design out. Carrying the fingerprint lets the score
    /// disappear by itself when it stops being true.
    struct ScoreStamp: Codable {
        var value: Int
        var fingerprint: String
        var computedAt: Date
    }

    /// What the library list needs, and nothing else.
    struct Summary: Identifiable, Hashable {
        var id: UUID
        /// The role this resume is for — the heading in the list.
        var title: String
        /// Employer, or the candidate's name when there is no employer to show.
        var subtitle: String
        var updatedAt: Date
        /// nil when the resume has never been scored, or has been edited since it was.
        var score: Int?
        /// Whether this record holds enough to render a document worth sending.
        var canShare: Bool
        /// Everything the search field matches against, pre-lowercased.
        var haystack: String

        func matches(_ query: String) -> Bool {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return true }
            return trimmed
                .split(separator: " ")
                .allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: - Locations

    private static let folderName = "Resumes"
    private static let legacyDraftFileName = "resume-draft.json"

    private static var applicationSupport: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
    }

    private static var folderURL: URL? {
        guard let applicationSupport else { return nil }
        let folder = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            guard (try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true
            )) != nil else { return nil }
            try? excludeFromBackup(folder)
        }
        return folder
    }

    private static func fileURL(for id: UUID) -> URL? {
        folderURL?.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Reading

    /// Every saved resume, newest first.
    ///
    /// Decodes a reduced shape rather than the full record: a stored photo is base64 in JSON,
    /// and materialising one per row only to throw it away is the one genuinely expensive part
    /// of opening this screen. `JSONDecoder` ignores keys the target type doesn't declare, so
    /// leaving `photoData` out of ``SummaryRecord`` is enough to skip decoding it.
    static func summaries() -> [Summary] {
        guard let folderURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: folderURL, includingPropertiesForKeys: nil
              )
        else { return [] }

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Summary? in
                guard let data = try? Data(contentsOf: url),
                      let record = try? decoder.decode(SummaryRecord.self, from: data)
                else {
                    // A record written by an older build whose shape no longer decodes isn't an
                    // error worth surfacing — drop it from the list rather than failing to show
                    // the others. It stays on disk, so a future build could still read it.
                    return nil
                }
                return record.summary
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func load(id: UUID) -> SavedResume? {
        guard let url = fileURL(for: id),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SavedResume.self, from: data)
        } catch {
            print("[ResumeLibrary] discarding unreadable resume \(id): \(error)")
            delete(id: id)
            return nil
        }
    }

    static var count: Int { summaries().count }

    static var isEmpty: Bool { count == 0 }

    // MARK: - Writing

    /// True when a resume holds anything the user actually typed. An untouched form shouldn't
    /// leave a file on disk, and shouldn't appear in the library as a resume you can open.
    static func isWorthSaving(_ resume: SavedResume) -> Bool {
        let experience = resume.experience
        let typedSomething = ![
            experience.fullName, experience.currentRole, experience.email, experience.phone,
            experience.location, experience.linkedIn, experience.portfolio, experience.summary,
            resume.jobTarget.title, resume.jobTarget.company, resume.jobTarget.descriptionText
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return typedSomething
            || !experience.skills.isEmpty
            || experience.photoData != nil
            || !experience.completedPositions.isEmpty
            || !experience.completedEducation.isEmpty
    }

    /// Writes a resume, stamping it with a fresh fingerprint and modification date.
    ///
    /// Emptying a resume's every field deletes it rather than leaving the previous contents on
    /// disk — otherwise clearing the form would look like it worked while the old resume stayed
    /// in the library.
    ///
    /// `modifiedAt` exists so tests and previews can lay out a library with a known order; the
    /// app always takes the default.
    @discardableResult
    static func save(_ resume: SavedResume, modifiedAt: Date = Date()) -> Bool {
        guard let url = fileURL(for: resume.id) else { return false }
        guard isWorthSaving(resume) else {
            delete(id: resume.id)
            return false
        }

        var record = resume
        record.updatedAt = modifiedAt
        record.contentFingerprint = fingerprint(
            experience: record.experience, jobTarget: record.jobTarget
        )

        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            // A failed save must never interrupt what the user is doing — the resume is still
            // intact in memory, and the next save attempt may well succeed.
            print("[ResumeLibrary] save failed: \(error)")
            return false
        }
    }

    static func delete(id: UUID) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        guard let folderURL else { return }
        try? FileManager.default.removeItem(at: folderURL)
        clearLegacyDraft()
    }

    // MARK: - Fingerprinting

    /// A digest of everything a score depends on.
    ///
    /// The field list is deliberate rather than "encode the whole struct": a photo, a phone
    /// number and a LinkedIn URL are all stored on the resume but none of them move the score,
    /// so changing one shouldn't throw away a score that is still accurate.
    static func fingerprint(experience: ExperienceInput, jobTarget: JobTarget) -> String {
        var parts: [String] = [
            experience.fullName,
            experience.currentRole,
            experience.summary,
            experience.yearsOfExperience,
            experience.skills.joined(separator: "\u{1F}"),
            jobTarget.title,
            jobTarget.company,
            jobTarget.descriptionText
        ]
        for position in experience.positions {
            parts.append(contentsOf: [
                position.title, position.company, position.location,
                position.startDate, position.endDate, String(position.isCurrent),
                position.bullets.joined(separator: "\u{1F}")
            ])
        }
        for entry in experience.educationEntries {
            parts.append(contentsOf: [
                entry.degree, entry.school, entry.location, entry.graduationDate
            ])
        }

        let joined = parts.joined(separator: "\u{1E}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Sharing one resume

    /// Renders a saved resume as a real PDF or Word file, ready to hand to the share sheet.
    ///
    /// Goes through the same `PDFDocumentRenderer` / `WordDocumentRenderer` as the in-app
    /// download, with the record's own template and photo, so a resume shared from the library
    /// is the same document the user saw when they made it — not a second rendering of it.
    ///
    /// Returns nil when the record has nothing worth sending, rather than producing a page with
    /// a name at the top and nothing under it.
    static func shareableFile(for id: UUID, format: ExportFormat) -> URL? {
        guard let resume = load(id: id), let body = resume.shareableBody() else { return nil }

        let data = format == .pdf
            ? PDFDocumentRenderer.render(
                title: "Resume", body: body,
                style: resume.templateStyle, photoData: resume.experience.photoData
            )
            : WordDocumentRenderer.render(
                title: "Resume", body: body,
                style: resume.templateStyle, photoData: resume.experience.photoData
            )
        guard !data.isEmpty else { return nil }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(shareFilename(for: resume)).\(format.fileExtension)")
        // Protected while it waits in the temporary directory for the share sheet, same as the
        // record it came from.
        guard (try? data.write(to: destination, options: [.atomic, .completeFileProtection])) != nil
        else { return nil }
        return destination
    }

    /// "Jane-Doe-Operations-Manager" — recognisable in a recruiter's inbox rather than
    /// "Resume.pdf" among forty others.
    static func shareFilename(for resume: SavedResume) -> String {
        let role = [resume.jobTarget.title, resume.experience.currentRole]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let parts = [resume.experience.fullName.trimmingCharacters(in: .whitespaces), role ?? ""]
            .filter { !$0.isEmpty }
        let name = parts.isEmpty ? "Resume" : parts.joined(separator: " ")

        // Anything a filesystem or a mail client might choke on becomes a hyphen. Letters from
        // any script are kept — a Hebrew or Japanese name shouldn't come out as "----".
        let sanitised = name.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-" && result.last == "-" { return }
                result.append(character)
            }
        return sanitised.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty
            ? "Resume"
            : String(sanitised.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(60))
    }

    // MARK: - Export

    /// Everything the app holds about you, as readable JSON, written somewhere the share sheet
    /// can reach.
    ///
    /// There is no server to request a copy from, so "export my data" is simply handing back the
    /// files that exist. Returns nil when there's nothing stored.
    static func exportForSharing() -> URL? {
        let resumes = summaries().compactMap { load(id: $0.id) }
        guard !resumes.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(resumes) else { return nil }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("rolvexa-my-data.json")
        // Protected while it waits in the temporary directory for the share sheet, same as the
        // records it came from.
        guard (try? data.write(to: destination, options: [.atomic, .completeFileProtection])) != nil
        else { return nil }
        return destination
    }

    // MARK: - Migration

    /// Moves the single `resume-draft.json` written by earlier builds into the library.
    ///
    /// Idempotent, and safe to call on every launch: it does nothing once the old file is gone.
    /// Shipping the library without this would quietly lose whatever the user had in progress
    /// when they updated.
    static func migrateLegacyDraftIfNeeded() {
        guard let applicationSupport else { return }
        let legacy = applicationSupport.appendingPathComponent(legacyDraftFileName)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }

        defer { clearLegacyDraft() }

        guard let data = try? Data(contentsOf: legacy),
              let draft = try? JSONDecoder().decode(LegacyDraft.self, from: data) else { return }

        let migrated = SavedResume(
            experience: draft.experience,
            jobTarget: draft.jobTarget,
            templateStyle: draft.templateStyle,
            createdAt: draft.savedAt,
            updatedAt: draft.savedAt,
            contentFingerprint: fingerprint(
                experience: draft.experience, jobTarget: draft.jobTarget
            )
            // `bodyText` is left nil on purpose. The old store never persisted an uploaded
            // resume's extracted text either, so there is nothing to carry across — the
            // structured fields are all these drafts ever held, and `shareableBody()` rebuilds
            // from exactly those.
        )
        // Carries the old file's timestamp across rather than taking the default of "now".
        // A resume the user last touched in March shouldn't appear in the library as edited
        // seconds ago just because they installed an update.
        save(migrated, modifiedAt: draft.savedAt)
    }

    private static func clearLegacyDraft() {
        guard let applicationSupport else { return }
        try? FileManager.default.removeItem(
            at: applicationSupport.appendingPathComponent(legacyDraftFileName)
        )
    }

    /// The shape earlier builds wrote. Kept only so ``migrateLegacyDraftIfNeeded()`` can read it.
    private struct LegacyDraft: Decodable {
        var experience: ExperienceInput
        var jobTarget: JobTarget
        var templateStyle: ResumeTemplateStyle
        var savedAt: Date
    }

    // MARK: - Private

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }

    /// The reduced shape decoded for the list. See ``summaries()``.
    ///
    /// Everything the list needs is here except `photoData`, which is the one field expensive to
    /// decode — base64 image bytes per row, materialised only to be thrown away.
    private struct SummaryRecord: Decodable {
        struct Experience: Decodable {
            var fullName: String
            var currentRole: String
            var summary: String
            var skills: [String]
            var positions: [Position]
            var educationEntries: [Education]

            struct Position: Decodable {
                var title: String
                var company: String
                var bullets: [String]

                /// Mirrors `WorkExperienceEntry.isComplete`.
                var isComplete: Bool {
                    !title.trimmingCharacters(in: .whitespaces).isEmpty
                        && !company.trimmingCharacters(in: .whitespaces).isEmpty
                        && bullets.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                }
            }

            struct Education: Decodable {
                var degree: String
                var school: String

                /// Mirrors `EducationEntry.isComplete`.
                var isComplete: Bool {
                    !degree.trimmingCharacters(in: .whitespaces).isEmpty
                        && !school.trimmingCharacters(in: .whitespaces).isEmpty
                }
            }
        }

        var id: UUID
        var experience: Experience
        var jobTarget: JobTarget
        var updatedAt: Date
        var contentFingerprint: String
        var score: ScoreStamp?
        var bodyText: String?

        var summary: Summary {
            let role = [jobTarget.title, experience.currentRole, experience.positions.first?.title]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            let employer = [jobTarget.company, experience.positions.first?.company]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            let name = experience.fullName.trimmingCharacters(in: .whitespaces)

            let haystack = ([role, employer].compactMap { $0 } + [name] + experience.skills)
                .joined(separator: " ")
                .lowercased()

            // A name and a job title alone render as a heading with nothing under it. Offering
            // to share that would let someone send a recruiter an empty page believing it was
            // their resume.
            let hasBody = bodyText.map(ResumeExportText.hasBodyWorthSharing) ?? false
            let hasStructure = experience.positions.contains(where: \.isComplete)
                || experience.educationEntries.contains(where: \.isComplete)
                || !experience.skills.isEmpty
                || !experience.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            return Summary(
                id: id,
                // "Untitled resume" rather than a guess: a resume saved before any role was
                // entered genuinely has no title, and inventing one would mislabel the row.
                title: role ?? (name.isEmpty ? "Untitled resume" : name),
                subtitle: employer ?? (role == nil ? "" : name),
                updatedAt: updatedAt,
                score: score?.fingerprint == contentFingerprint ? score?.value : nil,
                canShare: hasBody || hasStructure,
                haystack: haystack
            )
        }
    }
}
