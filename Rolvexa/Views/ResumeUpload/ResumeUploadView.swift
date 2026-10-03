import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import PhotosUI

struct ResumeUploadView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var isImporterPresented = false
    @State private var selectedFileName: String?
    @State private var selectedFileURL: URL?
    /// Set instead of `selectedFileURL` when the resume came from the photo library, which hands
    /// back bytes rather than a file on disk.
    @State private var selectedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isAnalyzing = false
    @State private var photoLoadFailed = false

    private var docxType: UTType { UTType(filenameExtension: "docx") ?? .data }

    private var hasSelection: Bool {
        selectedFileURL != nil || selectedImageData != nil
    }

    /// Lowercased extension of whatever is currently selected, used to pick the extraction path.
    private var selectedFileExtension: String {
        if let selectedFileURL { return selectedFileURL.pathExtension.lowercased() }
        return (selectedFileName as NSString?)?.pathExtension.lowercased() ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                dropzone

                if let selectedFileName {
                    selectedFileRow(name: selectedFileName)
                }

                whatYouGet

                Label("Your file is only used to generate this review and is never shared.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button {
                    analyze()
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text(isAnalyzing ? "Analyzing…" : "Analyze My Resume")
                    }
                }
                .buttonStyle(.primaryGradient)
                .disabled(!hasSelection || isAnalyzing)
            }
            .padding(20)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .appTrailing) {
                Label("Resume Review", systemImage: "doc.text")
                    .font(.caption.bold())
                    .foregroundStyle(Color.indigo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.indigo.opacity(0.12)))
            }
        }
        // `.image` covers JPEG/PNG/HEIC and friends, so a resume saved to Files as a photo or
        // screenshot is accepted alongside real documents.
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf, docxType, .image]) { result in
            if case .success(let url) = result {
                clearSelection()
                selectedFileName = url.lastPathComponent
                selectedFileURL = url
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
        .alert("Couldn't read that image", isPresented: $photoLoadFailed) {
            Button("OK") { photoLoadFailed = false }
        } message: {
            Text("Try picking it again, or export it to Files and upload it from there.")
        }
    }

    private func clearSelection() {
        selectedFileName = nil
        selectedFileURL = nil
        selectedImageData = nil
    }

    /// Photos hands back bytes rather than a URL, so the image is kept in memory and the
    /// filename/extension are derived from the item's own content type.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            selectedPhotoItem = nil
            photoLoadFailed = true
            return
        }
        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        clearSelection()
        selectedImageData = data
        selectedFileName = "Resume photo.\(fileExtension)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review your resume")
                .font(.title2.bold())
            Text("Get an instant AI score and tips to improve it")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dropzone: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.indigo.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.indigo)
                }

            Text("Tap to upload your resume")
                .font(.subheadline.bold())
            Text("PDF, Word, or a photo of your resume")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Browse Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
    }

    private func selectedFileRow(name: String) -> some View {
        let isImage = ResumeTextExtraction.isImageFileExtension(selectedFileExtension)
        return HStack(spacing: 12) {
            Image(systemName: isImage ? "photo.fill" : "doc.fill")
                .foregroundStyle(isImage ? Color.indigo : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(isImage ? "Ready to scan for text" : "Ready to analyze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                clearSelection()
                selectedPhotoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.appCardBackground))
    }

    private var whatYouGet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOU'LL GET")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                featureBadge(icon: "speedometer", title: "AI Score")
                featureBadge(icon: "textformat.abc", title: "Grammar & Clarity")
                featureBadge(icon: "checkmark.seal", title: "ATS Check")
            }
        }
    }

    private func featureBadge(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.indigo.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: icon)
                        .foregroundStyle(Color.indigo)
                }
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func extractText(from url: URL) -> String? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return ResumeTextExtraction.extractText(from: url, fileExtension: url.pathExtension)
    }

    /// Keeps the original file's exact bytes around so "Use Uploaded File" can show and export
    /// the real document later — plain-text extraction alone can never reproduce the actual
    /// visual layout (columns, fonts, images), since PDF text extraction order frequently
    /// doesn't even match reading order in the first place.
    private func readFileData(from url: URL) -> Data? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    private func looksLikeNameFragment(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= 20 else { return false }
        guard !line.contains(where: { $0.isNumber }), !line.contains("@") else { return false }
        // A single capitalized word (or hyphenated/apostrophe'd name like "O'Brien" / "Anne-Marie")
        // with no spaces — i.e. exactly one name part, not a title or sentence.
        return !line.contains(" ") && line.first?.isUppercase == true
    }

    private func looksLikeNameLine(_ line: String) -> Bool {
        // Rules out lines that are clearly something else that happened to extract before the
        // name (contact info, a "City, Region" location, an email, a phone number) — none of
        // which a person's name ever looks like.
        guard !line.isEmpty, line.count <= 40 else { return false }
        guard !line.contains(","), !line.contains("@"), !line.contains(where: { $0.isNumber }) else { return false }
        return true
    }

    private func guessedName(fromText text: String?, filename: String, excludingLocation location: String?) -> String {
        if let text {
            // A city name that word-wraps across two PDF lines (e.g. "Rishon" / "LeZion,
            // Israel") leaves a comma-free fragment ("Rishon") that would otherwise sail
            // through the name filter above untouched. Once the real location is known,
            // exclude any line that's just one of its words.
            let locationWords = Set(
                (location ?? "")
                    .split(separator: " ")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")).lowercased() }
                    .filter { !$0.isEmpty }
            )

            let nonEmptyLines = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter(looksLikeNameLine)
                .filter { !locationWords.contains($0.lowercased()) }

            if let firstLine = nonEmptyLines.first, firstLine.count <= 40 {
                if firstLine.contains(" ") {
                    // Already a full "First Last" (or more) on one line.
                    return firstLine
                }
                // Many resume templates style first/last name with different fonts or weights
                // (e.g. "Priya" normal, "Singh" bold), which PDF text extraction commonly emits
                // as two separate lines. Merge exactly the first two fragments (first + last
                // name) and stop there — anything greedier risks swallowing whatever comes
                // right after the name (e.g. a city/location line directly below it).
                if nonEmptyLines.count > 1, looksLikeNameFragment(nonEmptyLines[1]) {
                    return "\(firstLine) \(nonEmptyLines[1])"
                }
                return firstLine
            }
        }
        let base = (filename as NSString).deletingPathExtension
        let cleaned = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let withoutResumeWord = cleaned
            .replacingOccurrences(of: "resume", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return withoutResumeWord.isEmpty ? cleaned : withoutResumeWord
    }

    private func nonEmptyTrimmedLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private struct ParsedContactLine {
        var lineIndex: Int
        var phone: String?
        var email: String?
        var location: String?
    }

    /// Many resume templates render the header as a single "phone | email | city, country" line.
    /// This is a much more reliable anchor than assuming any particular part of the document is
    /// "near the top" — PDF text extraction order doesn't always match visual layout, and for some
    /// templates the whole name/title/contact header actually extracts *after* the entire body
    /// (Professional Summary, Experience, Education), not before it.
    private func findPipeContactLine(in lines: [String]) -> ParsedContactLine? {
        for (index, line) in lines.enumerated() {
            guard line.contains("|") else { continue }
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }

            var phone: String?
            var email: String?
            var location: String?
            for part in parts {
                if email == nil, part.contains("@") {
                    email = extractEmail(from: part) ?? part
                } else if phone == nil, let matchedPhone = extractPhone(from: part) {
                    phone = matchedPhone
                } else if location == nil, part.contains(",") {
                    location = part
                }
            }

            if email != nil || phone != nil {
                return ParsedContactLine(lineIndex: index, phone: phone, email: email, location: location)
            }
        }
        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }

    /// Picks the candidate's own address when a resume lists more than one.
    ///
    /// Taking the first match in reading order is wrong for the common "REFERENCE" block naming
    /// someone else — on a sidebar layout that referee's address is read before the candidate's
    /// own, so the finished resume ends up headed with a stranger's email. An address whose local
    /// part shares a word with the candidate's name is almost certainly theirs.
    private func bestEmail(in text: String, name: String) -> String? {
        let emails = allMatches(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text)
        guard !emails.isEmpty else { return nil }
        let nameTokens = name.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 }
        if !nameTokens.isEmpty {
            let owned = emails.first { email in
                let localPart = email.split(separator: "@").first.map(String.init)?.lowercased() ?? ""
                return nameTokens.contains { localPart.contains($0) }
            }
            if let owned { return owned }
        }
        return emails.first
    }

    private func extractEmail(from text: String) -> String? {
        firstMatch(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text)
    }

    private func extractPhone(from text: String) -> String? {
        firstMatch(pattern: #"(\+?\d{1,2}[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}"#, in: text)
    }

    // "City, XX" where XX is 2 letters, or "City, Country/Region" (up to 3 words) — covers both
    // US-style "San Jose, CA" and international "Rishon LeZion, Israel" formats.
    private static let locationPattern = #"\b[A-Z][a-zA-Z.]+(?:\s[A-Z][a-zA-Z.]+)*,\s([A-Z]{2}|[A-Z][a-zA-Z]+(?:\s[A-Z][a-zA-Z]+){0,2})\b(?:\s\d{5})?"#

    private static let usStateAbbreviations: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY", "DC", "PR"
    ]

    /// Rejects matches like "Dell, HP" — the regex alone can't tell a brand-name pair from a
    /// real "City, ST" location, so any 2-letter region part must be a real US state code.
    /// Anything longer (a country/region name) is accepted as-is.
    private func isPlausibleLocation(_ match: String) -> Bool {
        guard let commaIndex = match.firstIndex(of: ",") else { return false }
        let afterComma = match[match.index(after: commaIndex)...].trimmingCharacters(in: .whitespaces)
        let regionPart = afterComma.split(separator: " ").first.map(String.init) ?? afterComma
        if regionPart.count == 2 {
            return Self.usStateAbbreviations.contains(regionPart.uppercased())
        }
        return regionPart.count > 2
    }

    private func allMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func extractLocation(from text: String) -> String? {
        // Multi-column resume layouts (photo/contact sidebar + main content) often extract
        // in an order that doesn't match visual reading order, so a plain "first match in the
        // whole document" search can latch onto an unrelated city (a past employer's office,
        // a school's city, etc). Anchor the search to the lines right around the email/phone
        // instead, since those are reliably part of the same contact-info cluster.
        //
        // Narrow sidebar columns also frequently word-wrap a multi-word city across two
        // extracted lines (e.g. "Mountain" / "View, CA"), so the nearby window is joined with
        // spaces rather than newlines — otherwise a line-anchored regex would only ever see
        // the second fragment and misread "View, CA" as the whole city.
        let lines = text.components(separatedBy: .newlines)
        let anchorIndex = lines.firstIndex { line in
            extractEmail(from: line) != nil || extractPhone(from: line) != nil
        }

        if let anchorIndex {
            let start = max(0, anchorIndex - 4)
            let end = min(lines.count - 1, anchorIndex + 4)
            let nearby = lines[start...end]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            if let match = allMatches(pattern: Self.locationPattern, in: nearby).first(where: isPlausibleLocation) {
                return match
            }
        }

        let wholeDocument = text.replacingOccurrences(of: "\n", with: " ")
        return allMatches(pattern: Self.locationPattern, in: wholeDocument).first(where: isPlausibleLocation)
    }

    /// For templates where the header block (name/title/contact) extracts as a unit placed
    /// elsewhere in the document, the professional-summary paragraph commonly sits directly
    /// after the contact line — disconnected from its own "PROFESSIONAL SUMMARY" header, which
    /// stays behind near the top of the document with no body under it. Joined with spaces
    /// since this is flowing prose, not a bulleted list.
    private func extractSummary(afterContactLineIndex contactIndex: Int, in lines: [String]) -> (text: String, endIndex: Int)? {
        var result: [String] = []
        var i = contactIndex + 1
        while i < lines.count, result.count < 8 {
            let line = lines[i]
            if ResumeSectionKit.isSectionHeader(line) { break }
            result.append(line)
            i += 1
        }
        guard !result.isEmpty else { return nil }
        return (result.joined(separator: " "), i - 1)
    }

    private func extractEducation(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let body = ResumeSectionKit.sectionBody(afterHeaderContaining: ["EDUCATION"], in: lines, maxLines: 3)
        guard !body.isEmpty else { return nil }
        return body.joined(separator: "\n")
    }

    private func unreadableFileAdvice(for fileExtension: String) -> String {
        if ResumeTextExtraction.isImageFileExtension(fileExtension) {
            return "We couldn't find readable text in this photo. Try again in brighter, even lighting with the page flat and filling the frame, and make sure the whole resume is in focus."
        }
        if fileExtension == "pdf" {
            return "This PDF may be a scanned image with text too faint or stylized for on-device OCR to read. Try a clearer scan or a text-based PDF."
        }
        return "This DOCX file's contents couldn't be read — please try a PDF instead."
    }

    private func buildReview(from text: String?, fileExtension: String) async -> ResumeReview {
        guard let text else {
            return ResumeReview(
                overallScore: 0,
                breakdown: [
                    ResumeScoreBreakdown(title: "ATS Compatibility", percent: 0, icon: "checkmark.seal"),
                    ResumeScoreBreakdown(title: "Content & Impact", percent: 0, icon: "target"),
                    ResumeScoreBreakdown(title: "Grammar & Clarity", percent: 0, icon: "textformat.abc"),
                    ResumeScoreBreakdown(title: "Formatting", percent: 0, icon: "square.grid.2x2")
                ],
                suggestions: [
                    ImprovementSuggestion(
                        title: "We couldn't read this file",
                        detail: unreadableFileAdvice(for: fileExtension)
                    )
                ]
            )
        }

        // Real, fully offline analysis — NaturalLanguage tokenization + the system spell
        // checker + deterministic heuristics (see ResumeAnalysisEngine). No network access, no
        // bundled language model, ever.
        return await ResumeAnalysisEngine.buildReview(from: text)
    }

    private func analyze() {
        guard let selectedFileName, hasSelection else { return }
        isAnalyzing = true
        appState.uploadedFileName = selectedFileName
        let fileExtension = selectedFileExtension
        let imageData = selectedImageData
        let fileURL = selectedFileURL

        Task {
            // Two sources: a document/image picked from Files (a URL), or a photo picked from
            // the library (raw bytes, no file on disk). OCR is identical either way.
            let extractedText: String?
            if let imageData {
                extractedText = ResumeTextExtraction.extractFromImageData(imageData)
                appState.uploadedResumeFileData = imageData
            } else if let fileURL {
                extractedText = extractText(from: fileURL)
                appState.uploadedResumeFileData = readFileData(from: fileURL)
            } else {
                extractedText = nil
            }
            appState.uploadedResumeFileExtension = fileExtension
            try? await Task.sleep(for: .seconds(1))

            appState.extractedResumeText = extractedText
            appState.resumeReview = await buildReview(from: extractedText, fileExtension: fileExtension)

            if let extractedText {
                let lines = nonEmptyTrimmedLines(extractedText)
                let pipeContact = findPipeContactLine(in: lines)

                if let pipeContact {
                    let nameIndex = pipeContact.lineIndex - 2
                    let titleIndex = pipeContact.lineIndex - 1
                    if nameIndex >= 0, looksLikeNameLine(lines[nameIndex]) {
                        appState.experience.fullName = lines[nameIndex]
                    }
                    if titleIndex >= 0, titleIndex != nameIndex {
                        appState.experience.currentRole = lines[titleIndex]
                    }
                    appState.extractedEmail = pipeContact.email ?? bestEmail(in: extractedText, name: appState.experience.fullName)
                    appState.extractedPhone = pipeContact.phone ?? extractPhone(from: extractedText)
                    appState.extractedLocation = pipeContact.location ?? extractLocation(from: extractedText)

                    let summaryResult = extractSummary(afterContactLineIndex: pipeContact.lineIndex, in: lines)
                    appState.extractedSummary = summaryResult?.text
                } else {
                    let location = extractLocation(from: extractedText)
                    appState.experience.fullName = guessedName(fromText: extractedText, filename: selectedFileName, excludingLocation: location)
                    appState.extractedEmail = bestEmail(in: extractedText, name: appState.experience.fullName)
                    appState.extractedPhone = extractPhone(from: extractedText)
                    appState.extractedLocation = location
                }

                // Strip the name/role/contact/summary block out of the body text, regardless of
                // which detection branch ran above. The preview and the templated export both
                // render that block themselves as a structured header, so anything left in the
                // body shows up a second time. This previously only happened when a pipe-style
                // contact line was found, which left every other layout — and most OCR'd photos
                // — showing the name, email and phone twice.
                appState.extractedResumeDisplayText = ResumeSectionKit.removingHeaderBlock(
                    from: extractedText,
                    name: appState.experience.fullName,
                    role: appState.experience.currentRole,
                    summary: appState.extractedSummary ?? "",
                    email: appState.extractedEmail,
                    phone: appState.extractedPhone,
                    location: appState.extractedLocation
                )

                appState.extractedEducation = extractEducation(from: extractedText)
                appState.experience.skills = ResumeSectionKit.extractSkills(from: extractedText)

                // Falls back to the Experience section's most recent entry when the near-contact-
                // line heuristic above didn't find a title (e.g. no pipe-separated contact line).
                //
                // Deliberately runs *after* the header strip above: a role recovered from the
                // Experience section is a real body line describing a job, not a header subtitle,
                // so it must stay in the body. Only a role found next to the contact line (the
                // pipe branch, which sets it before the strip) gets removed.
                let recentPosition = ResumeSectionKit.extractMostRecentPosition(from: extractedText)
                if appState.experience.currentRole.isEmpty, let title = recentPosition.title {
                    appState.experience.currentRole = title
                }
                appState.extractedCompany = recentPosition.company
            } else {
                appState.experience.fullName = guessedName(fromText: nil, filename: selectedFileName, excludingLocation: nil)
            }

            isAnalyzing = false
            router.push(.resumeReview)
        }
    }
}

#Preview {
    NavigationStack {
        ResumeUploadView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
