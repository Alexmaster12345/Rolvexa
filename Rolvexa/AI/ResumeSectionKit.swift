import Foundation
import NaturalLanguage

/// Shared, purely deterministic resume-text parsing helpers — section header detection, section
/// body extraction, and skill/keyword mining. Runs entirely on-device via simple string
/// heuristics and the `NaturalLanguage` framework's tokenizer/tagger — no network access, no
/// bundled language model, ever.
enum ResumeSectionKit {
    /// A short, all-caps line with at least one letter (e.g. "SUMMARY", "EXPERIENCE") — the
    /// header style used by the overwhelming majority of resume templates.
    static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 32 else { return false }
        guard trimmed.contains(where: { $0.isLetter }) else { return false }
        return trimmed == trimmed.uppercased()
    }

    /// Standard resume section names mapped to the header keywords (already whitespace-compact
    /// and uppercased) that identify them — covers the common synonyms real resumes use.
    static let standardSectionKeywords: [String: [String]] = [
        "Summary": ["SUMMARY", "PROFILE", "OBJECTIVE", "ABOUTME"],
        "Experience": ["EXPERIENCE", "EMPLOYMENT", "WORKHISTORY"],
        "Education": ["EDUCATION", "ACADEMIC"],
        "Skills": ["SKILL", "COMPETENC"],
        "Certifications": ["CERTIFICATION", "LICENSE"],
        "Projects": ["PROJECT"]
    ]

    /// Which of the standard resume sections this text appears to have, based on header lines
    /// alone — used for structure-completeness scoring.
    static func detectedSections(in text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.components(separatedBy: .newlines) where isSectionHeader(line) {
            // Many resume templates render section headers with letter-spacing (e.g.
            // "E D U C A T I O N"), which PDF/OCR text extraction reproduces as literal space
            // characters between every letter — compact those out before matching.
            let compact = line.uppercased().replacingOccurrences(of: " ", with: "")
            for (section, keywords) in standardSectionKeywords where keywords.contains(where: compact.contains) {
                found.insert(section)
            }
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
            guard lowercasedText.contains(keyword.lowercased()) else { continue }
            found.append(keyword)
            if found.count >= 10 { break }
        }
        return found
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
                if word.count > 2, !keywordStopwords.contains(word), word.rangeOfCharacter(from: .decimalDigits) == nil {
                    frequencies[word, default: 0] += 1
                }
            }
            return true
        }
        return frequencies.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }
}
