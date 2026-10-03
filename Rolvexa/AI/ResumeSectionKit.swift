import Foundation
import NaturalLanguage

/// Shared, purely deterministic resume-text parsing helpers — section header detection, section
/// body extraction, and skill/keyword mining. Runs entirely on-device via simple string
/// heuristics and the `NaturalLanguage` framework's tokenizer/tagger — no network access, no
/// bundled language model, ever.
nonisolated enum ResumeSectionKit {
    /// A short, all-caps line with at least one letter (e.g. "SUMMARY", "EXPERIENCE") — the
    /// header style used by the overwhelming majority of resume templates.
    static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 32 else { return false }
        guard trimmed.contains(where: { $0.isLetter }) else { return false }

        // Hebrew, Arabic, CJK, Thai and other caseless scripts satisfy
        // `trimmed == trimmed.uppercased()` unconditionally, so the all-caps test classified
        // *every* short line of a Hebrew resume as a heading — the candidate's name, the
        // employer line, even bullet text. `detectedSections` then found no standard sections at
        // all and the scorer docked 8 points for each one it thought was missing.
        //
        // Where there's no case to read, a line is a heading only if it matches the known
        // section vocabulary below.
        let hasCasedLetters = trimmed.contains { $0.lowercased() != $0.uppercased() }
        guard hasCasedLetters else { return matchesStandardSectionName(trimmed) }

        return trimmed == trimmed.uppercased()
    }

    /// Whether a line names one of the standard resume sections, in any supported language.
    static func matchesStandardSectionName(_ line: String) -> Bool {
        !sections(named: line).isEmpty
    }

    private static func sections(named line: String) -> Set<String> {
        // Letter-spaced headings ("E D U C A T I O N") survive extraction as literal spaces, so
        // they're compacted out before matching.
        let compact = line.uppercased().replacingOccurrences(of: " ", with: "")
        var found: Set<String> = []
        for (section, keywords) in standardSectionKeywords where keywords.contains(where: compact.contains) {
            found.insert(section)
        }
        return found
    }

    /// Whole-token containment, shared by skill mining and job-fit matching.
    ///
    /// A plain `contains` matches "C" inside "Charge" and "R" inside "Registered", which put
    /// those two on the skills list of every resume that had no explicit skills section — a
    /// nurse's resume came back claiming C and R. Each edge of the term must sit against a token
    /// boundary, but only where that edge is itself part of a token, so "C++", "CI/CD" and
    /// "Node.js" still match their own punctuation. `+` and `#` count as continuations so "C"
    /// doesn't match inside "C++".
    static func containsWholeTerm(_ term: String, in haystack: String) -> Bool {
        let needle = term.lowercased()
        guard !needle.isEmpty else { return false }

        func continuesToken(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "+" || character == "#"
        }

        let checkLeading = needle.first.map(continuesToken) ?? false
        let checkTrailing = needle.last.map(continuesToken) ?? false

        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let leadingOK = !checkLeading || range.lowerBound == haystack.startIndex
                || !continuesToken(haystack[haystack.index(before: range.lowerBound)])
            let trailingOK = !checkTrailing || range.upperBound == haystack.endIndex
                || !continuesToken(haystack[range.upperBound])
            if leadingOK && trailingOK { return true }
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    /// Standard resume section names mapped to the header keywords (already whitespace-compact
    /// and uppercased) that identify them — covers the common synonyms real resumes use.
    /// Hebrew headings are listed beside the English ones rather than handled separately: a
    /// resume written in Israel is routinely bilingual, with Hebrew prose and English
    /// technology names in the same document.
    static let standardSectionKeywords: [String: [String]] = [
        "Summary": ["SUMMARY", "PROFILE", "OBJECTIVE", "ABOUTME", "תקציר", "אודות", "פרופיל"],
        "Experience": ["EXPERIENCE", "EMPLOYMENT", "WORKHISTORY", "ניסיון", "תעסוקה", "תעסוקתי"],
        "Education": ["EDUCATION", "ACADEMIC", "השכלה", "לימודים"],
        "Skills": ["SKILL", "COMPETENC", "כישורים", "מיומנויות"],
        "Certifications": ["CERTIFICATION", "LICENSE", "תעודות", "הסמכות"],
        "Projects": ["PROJECT", "פרויקטים"]
    ]

    /// Which of the standard resume sections this text appears to have, based on header lines
    /// alone — used for structure-completeness scoring.
    static func detectedSections(in text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.components(separatedBy: .newlines) where isSectionHeader(line) {
            found.formUnion(sections(named: line))
        }
        return found
    }

    /// The lines directly under the first header matching one of `keywords`, stopping at the
    /// next header or after `maxLines`, whichever comes first.
    static func sectionBody(afterHeaderContaining keywords: [String], in lines: [String], maxLines: Int) -> [String] {
        guard let headerIndex = lines.firstIndex(where: { line in
            guard isSectionHeader(line) else { return false }
            let compact = line.uppercased().replacingOccurrences(of: " ", with: "")
            return keywords.contains { compact.contains($0) }
        }) else { return [] }

        var result: [String] = []
        var i = headerIndex + 1
        while i < lines.count, result.count < maxLines {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }
            if isSectionHeader(line) { break }
            result.append(line)
            i += 1
        }
        return result
    }

    /// Many resume templates emit several section headers (e.g. "PROFESSIONAL SUMMARY",
    /// "EDUCATION", "TECHNICAL SKILLS") as bare stub lines with no body text actually following
    /// them — the real content for those sections got extracted elsewhere in the document
    /// instead. Displaying (or exporting) a bold header with literally nothing under it just
    /// reads as a broken/empty section, so drop any header whose next non-empty line is either
    /// another header or the end of the text.
    static func removeDanglingHeaders(_ lines: [String]) -> [String] {
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            if isSectionHeader(line) {
                var next = index + 1
                while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty {
                    next += 1
                }
                let hasRealBodyAfter = next < lines.count && !isSectionHeader(lines[next])
                if !hasRealBodyAfter {
                    continue
                }
            }
            result.append(line)
        }
        return result
    }

    // MARK: - Skill extraction

    static let knownSkillKeywords: [String] = [
        // Languages
        "Swift", "SwiftUI", "Objective-C", "Python", "JavaScript", "TypeScript", "Java", "Kotlin",
        "C#", "C++", "C", "Go", "Rust", "PHP", "Ruby", "R", "Scala", "SQL", "NoSQL", "Bash", "PowerShell",
        // Web / mobile frameworks
        "React", "React Native", "Angular", "Vue", "Node.js", "Next.js", "Express", "Django", "Flask",
        "Spring", "ASP.NET", "GraphQL", "REST", "API",
        // Data / ML
        "MongoDB", "MySQL", "PostgreSQL", "Redis", "Elasticsearch", "TensorFlow", "PyTorch",
        "scikit-learn", "Pandas", "NumPy", "Spark", "Hadoop", "Tableau", "Power BI", "Excel",
        // Cloud / DevOps
        "AWS", "Azure", "GCP", "Docker", "Kubernetes", "Terraform", "Ansible", "Jenkins", "CI/CD",
        "Git", "GitHub", "GitLab", "Linux", "Windows", "macOS", "VMware", "Nagios", "Zabbix", "PRTG",
        "Cisco", "TCP/IP", "DNS", "VPN", "Firewall",
        // Design
        "Figma", "Sketch", "Adobe XD", "Photoshop", "Illustrator", "InDesign", "Prototyping",
        "User Research", "Wireframing", "Product Design",
        // Business / soft skills / PM
        "Agile", "Scrum", "Kanban", "Jira", "Confluence", "ServiceNow", "Salesforce", "SAP",
        "Project Management", "Stakeholder Management", "Leadership", "Cross-functional",
        "DevOps", "SOC", "RCA", "Cybersecurity"
    ]

    /// Extracts a dedicated "Skills" section if the resume has one, falling back to scanning the
    /// whole document for known skill keywords when there's no explicit heading.
    static func extractSkills(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var body = sectionBody(afterHeaderContaining: ["TECHNICALSKILL"], in: lines, maxLines: 8)
        if body.isEmpty {
            body = sectionBody(afterHeaderContaining: ["SKILL"], in: lines, maxLines: 8)
        }
        if body.isEmpty {
            return fallbackSkills(from: text)
        }

        var items: [String] = []
        for line in body {
            let cleanedLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-*▪·‣ "))
                .trimmingCharacters(in: .whitespaces)
            guard !cleanedLine.isEmpty else { continue }
            if cleanedLine.contains(",") {
                items.append(contentsOf: cleanedLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            } else {
                items.append(cleanedLine)
            }
        }
        let filtered = items.filter { !$0.isEmpty }
        return filtered.isEmpty ? fallbackSkills(from: text) : filtered
    }

    static func fallbackSkills(from text: String) -> [String] {
        let lowercasedText = text.lowercased()
        var found: [String] = []
        for keyword in knownSkillKeywords {
            guard containsWholeTerm(keyword, in: lowercasedText) else { continue }
            found.append(keyword)
            if found.count >= 10 { break }
        }
        return found
    }

    // MARK: - Profile links

    static let linkDomains = [
        "linkedin.com", "github.com", "gitlab.com", "twitter.com", "x.com",
        "behance.net", "dribbble.com", "medium.com", "stackoverflow.com"
    ]

    private static let linkLabels: Set<String> = [
        "linkedin", "github", "gitlab", "twitter", "x", "portfolio", "website", "behance", "dribbble"
    ]

    /// Profile/portfolio URLs found anywhere in the resume, de-duplicated and in reading order.
    /// These belong with the contact details rather than loose in the body, so the exporters
    /// render them alongside the email and phone.
    static func extractLinks(from text: String) -> [String] {
        var found: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            for token in rawLine.split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "\t" }) {
                let candidate = String(token)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "•-*▪·‣,;()<>[] "))
                let lowered = candidate.lowercased()
                guard lowered.hasPrefix("http") || lowered.hasPrefix("www.")
                        || linkDomains.contains(where: lowered.contains) else { continue }
                // An email contains a domain too, but it isn't a profile link.
                guard !candidate.contains("@") else { continue }
                if !found.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                    found.append(candidate)
                }
            }
        }
        return found
    }

    // MARK: - Header de-duplication

    /// Strips the header block — name, role, contact details, summary — out of a resume body.
    ///
    /// Both the in-app preview (`ResumeTemplateCard`) and the templated export print that block
    /// themselves, as a structured header, so any copy still sitting in the body text renders a
    /// second time. Filtering is done by *content* rather than by line position, because the
    /// header doesn't reliably land in one contiguous run at the top: PDF and OCR extraction
    /// order often doesn't match visual order, and multi-column layouts can repeat the name in a
    /// sidebar or profile card.
    static func removingHeaderBlock(
        from text: String,
        name: String,
        role: String,
        summary: String,
        email: String?,
        phone: String?,
        location: String?
    ) -> String {
        let exactMatches: Set<String> = Set(
            ([name, role, summary] + [email, phone, location].compactMap { $0 })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // A short, digit-free line starting with the first name is almost always a second
        // rendering of the name (a sidebar profile card, a page header), which an exact match
        // can't catch when the surname extracted slightly differently.
        // Every part of the name, not just the first. A resume that sets the name in large
        // display type down a sidebar gets read back by OCR as separate lines — "ELLIOT" on one,
        // "ALDERSON" on another — so matching only the first word left the surname behind as a
        // stray line in the body.
        let nameTokens = name
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0).lowercased() }
            .filter { $0.count >= 2 }

        func looksLikeDuplicateNameLine(_ trimmed: String) -> Bool {
            guard !nameTokens.isEmpty else { return false }
            let words = trimmed.split(separator: " ")
            guard words.count <= 4, !trimmed.contains(where: \.isNumber) else { return false }
            // Only when the line is made up *entirely* of name parts, so a real sentence or a
            // job title that merely happens to contain a name word is kept.
            let lineTokens = trimmed
                .split(whereSeparator: { !$0.isLetter })
                .map { String($0).lowercased() }
                .filter { $0.count >= 2 }
            guard !lineTokens.isEmpty else { return false }
            return lineTokens.allSatisfy { nameTokens.contains($0) }
        }

        /// A line that is just a profile link (and the bare "LinkedIn:" style label above it).
        /// Those belong with the contact details, which render them separately, so they're
        /// stripped here rather than left loose in the body.
        func isLinkLine(_ trimmed: String) -> Bool {
            let lowered = trimmed.lowercased()
            guard trimmed.split(separator: " ").count <= 3 else { return false }
            if lowered.hasPrefix("http") || lowered.hasPrefix("www.") { return true }
            if linkDomains.contains(where: lowered.contains) { return true }
            // "LinkedIn:" / "Twitter:" labels sitting on their own line above the URL.
            let label = lowered.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return linkLabels.contains(label)
        }

        /// A line that is nothing but an email address (optionally behind a short label such as
        /// "Email:"), as opposed to prose that happens to mention one.
        func isStandaloneEmailLine(_ trimmed: String) -> Bool {
            guard trimmed.contains("@"), trimmed.count <= 60 else { return false }
            let words = trimmed.split(separator: " ")
            guard words.count <= 2 else { return false }
            return words.contains { $0.contains("@") && $0.contains(".") }
        }

        /// A bulleted or bare repeat of the phone number or location from the contact block.
        ///
        /// Exact matching isn't enough here: OCR frequently reads the same phone number
        /// differently in two places on the page ("+1-202-555-0199" in the header versus
        /// "+1-202-55-0178" in a sidebar bullet), so the digits are compared loosely by count
        /// rather than by value. Four-digit years and date ranges stay well under the threshold,
        /// so education and employment dates are untouched.
        func isRepeatedContactDetailLine(_ trimmed: String) -> Bool {
            let stripped = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-*▪·‣ "))
                .trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty, stripped.count <= 60 else { return false }

            if let location, !location.isEmpty,
               stripped.range(of: location, options: .caseInsensitive) != nil {
                return true
            }
            if phone != nil, stripped.filter(\.isNumber).count >= 9 {
                return true
            }
            return false
        }

        let filtered = text.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if exactMatches.contains(trimmed) { return false }
            // A combined "phone | email | location" line never equals any single field, and the
            // fields can appear in any order — the email is unique enough that any line
            // containing it is virtually always the contact line.
            if let email, !email.isEmpty, trimmed.contains(email) { return false }
            if let phone, !phone.isEmpty, trimmed.contains(phone) { return false }
            if looksLikeDuplicateNameLine(trimmed) { return false }
            // An exact match misses OCR near-misses: a photographed resume's sidebar can read
            // back as "ellit.alderson@fsociety.com" while the structured header holds the
            // correctly-read "elliot.alderson@fsociety.com", leaving the address printed twice.
            // Any short line that is essentially just an address is the contact email again —
            // the header already carries it, so it never needs to appear in the body.
            if email != nil, isStandaloneEmailLine(trimmed) { return false }
            if isRepeatedContactDetailLine(trimmed) { return false }
            if isLinkLine(trimmed) { return false }
            return true
        }

        // The summary can reappear wrapped across several lines, so no single line equals it.
        // Greedily grow a window of consecutive lines and drop the whole run once it
        // reconstructs a meaningful chunk of the summary.
        var deduped: [String] = []
        var index = 0
        while index < filtered.count {
            if !summary.isEmpty {
                var window = ""
                var lookahead = index
                while lookahead < filtered.count {
                    let candidate = filtered[lookahead].trimmingCharacters(in: .whitespaces)
                    guard !candidate.isEmpty else { break }
                    let grown = window.isEmpty ? candidate : window + " " + candidate
                    guard summary.contains(grown) else { break }
                    window = grown
                    lookahead += 1
                }
                if window.count >= min(summary.count, 60) {
                    index = lookahead
                    continue
                }
            }
            deduped.append(filtered[index])
            index += 1
        }

        return removeDanglingHeaders(deduped)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Most recent position

    /// Best-effort (title, company) for the first entry under the resume's "Experience" section
    /// — covers the common single-line layouts ("Title, Company", "Title at Company",
    /// "Title | Company") and the two-line layout (title on one line, company on the next).
    /// Assumes "Title <separator> Company" ordering, which is the dominant real-world
    /// convention; resumes using the reverse order will have title/company swapped.
    static func extractMostRecentPosition(from text: String) -> (title: String?, company: String?) {
        let lines = text.components(separatedBy: .newlines)
        let body = sectionBody(afterHeaderContaining: ["EXPERIENCE", "EMPLOYMENT", "WORKHISTORY"], in: lines, maxLines: 4)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "•-*▪·‣ ")).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !body.isEmpty else { return (nil, nil) }

        let separators = [" | ", " – ", " — ", " - ", ", ", " at ", " @ "]
        for line in body.prefix(2) {
            for separator in separators {
                guard let range = line.range(of: separator, options: .caseInsensitive) else { continue }
                let left = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !left.isEmpty, !right.isEmpty else { continue }
                return (left, right)
            }
        }
        // No separator on either of the first two lines — likely a two-line layout: title then
        // company (or vice versa) each on their own line.
        if body.count > 1 {
            return (body[0], body[1])
        }
        return (body[0], nil)
    }

    // MARK: - Keyword extraction

    /// Generic function words and resume filler that would otherwise pollute a noun/adjective
    /// frequency count — not a real "stopword list" for general English, just enough to keep
    /// keyword extraction useful for this specific purpose.
    private static let keywordStopwords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "have", "has", "had", "was", "were",
        "are", "been", "being", "will", "would", "could", "should", "about", "into", "over",
        "such", "some", "than", "then", "them", "they", "their", "there", "these", "those",
        "including", "etc", "role", "roles", "team", "teams", "work", "worked", "working",
        "responsible", "duties", "including", "years", "year", "experience", "resume"
    ]

    /// Top noun/adjective lemmas by frequency, lowercased — a lightweight stand-in for real
    /// keyword-extraction models, built entirely on `NLTagger` (part of `NaturalLanguage`, runs
    /// fully on-device with no model download).
    static func extractKeywords(from text: String, limit: Int = 20) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var frequencies: [String: Int] = [:]
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, tokenRange in
            if tag == .noun || tag == .adjective {
                let word = text[tokenRange].lowercased()
                if isUsableKeyword(word) {
                    frequencies[word, default: 0] += 1
                }
            }
            return true
        }

        // The part-of-speech model isn't guaranteed to be present: where it isn't, every token
        // comes back tagged `.otherWord` and this returned an empty list on every input —
        // silently disabling keyword extraction rather than degrading it. Fall back to plain
        // frequency over stopword-filtered tokens, which needs no model.
        if frequencies.isEmpty {
            for token in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            where isUsableKeyword(token) {
                frequencies[token, default: 0] += 1
            }
        }

        // Sort by frequency, then alphabetically — dictionary order is not stable between runs,
        // so without the tiebreak the same text could yield a different list each call.
        return frequencies
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    private static func isUsableKeyword(_ word: String) -> Bool {
        word.count > 3
            && !keywordStopwords.contains(word)
            && word.rangeOfCharacter(from: .decimalDigits) == nil
    }
}
