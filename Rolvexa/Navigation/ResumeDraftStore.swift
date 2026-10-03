import Foundation

/// Saves the in-progress resume so closing the app doesn't discard it.
///
/// Until this existed nothing was persisted at all: a user could fill in six jobs, get a phone
/// call, and come back to an empty form.
///
/// Writing a resume to disk in an app whose whole claim is privacy deserves care, so:
///
/// - It lives in Application Support, not Documents, so it isn't exposed through the Files app
///   or iTunes file sharing.
/// - It's written with `.completeFileProtection`, so iOS keeps it encrypted whenever the device
///   is locked and the key is unavailable even to this process.
/// - It's excluded from iCloud and iTunes backups — a résumé shouldn't silently propagate off
///   the device through a backup when the app promises it won't leave.
/// - ``clear()`` deletes it outright, and the app calls that when the user discards a draft.
///
/// This is the deliberate counterpart to the diagnostic dump that used to write the same data,
/// unprotected, to Documents on every upload as debugging scaffolding.
enum ResumeDraftStore {
    /// What's worth restoring. Deliberately not the whole of `AppState`: the uploaded file's raw
    /// bytes, the derived review and the generated kit are all large, cheap to recompute, or
    /// both — persisting them would multiply the on-disk footprint of the most sensitive data
    /// for no benefit.
    struct Draft: Codable {
        var experience: ExperienceInput
        var jobTarget: JobTarget
        var templateStyle: ResumeTemplateStyle
        var savedAt: Date
    }

    private static let fileName = "resume-draft.json"

    private static var fileURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return directory.appendingPathComponent(fileName)
    }

    /// True when the draft holds anything the user actually typed. An untouched form shouldn't
    /// leave a file on disk, and shouldn't offer to "restore" nothing on next launch.
    static func isWorthSaving(_ draft: Draft) -> Bool {
        let experience = draft.experience
        let typedSomething = ![
            experience.fullName, experience.currentRole, experience.email, experience.phone,
            experience.location, experience.linkedIn, experience.portfolio, experience.summary,
            draft.jobTarget.title, draft.jobTarget.company, draft.jobTarget.descriptionText
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return typedSomething
            || !experience.skills.isEmpty
            || experience.photoData != nil
            || !experience.completedPositions.isEmpty
            || !experience.completedEducation.isEmpty
    }

    @discardableResult
    static func save(_ draft: Draft) -> Bool {
        guard let fileURL else { return false }
        guard isWorthSaving(draft) else {
            clear()
            return false
        }
        do {
            let data = try JSONEncoder().encode(draft)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try excludeFromBackup(fileURL)
            return true
        } catch {
            // A failed draft save must never interrupt what the user is doing — the resume is
            // still intact in memory, and the next save attempt may well succeed.
            print("[ResumeDraftStore] save failed: \(error)")
            return false
        }
    }

    static func load() -> Draft? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Draft.self, from: data)
        } catch {
            // A draft written by an older build whose shape no longer decodes is not an error
            // worth surfacing; drop it and start clean rather than failing to launch.
            print("[ResumeDraftStore] discarding unreadable draft: \(error)")
            clear()
            return nil
        }
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var hasDraft: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Everything the app holds about you, as readable JSON, written somewhere the share sheet
    /// can reach.
    ///
    /// There is no server to request a copy from, so "export my data" is simply handing back the
    /// one file that exists. Returns nil when there's nothing stored.
    static func exportForSharing() -> URL? {
        guard let draft = load() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(draft) else { return nil }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("rolvexa-my-data.json")
        // Protected while it waits in the temporary directory for the share sheet, same as the
        // draft it came from.
        guard (try? data.write(to: destination, options: [.atomic, .completeFileProtection])) != nil else {
            return nil
        }
        return destination
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
}
