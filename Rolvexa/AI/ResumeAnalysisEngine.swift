import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ResumeAnalysisError: Error {
    case noImprovement
}

/// A fully offline resume-analysis engine: no cloud AI, no external AI APIs, no network access
/// at any point. Scoring and spelling/grammar detection run synchronously on-device using the
/// system spell checker (`UITextChecker`, iOS only) plus `NaturalLanguage` tokenization (via
/// `ResumeSectionKit`) and deterministic heuristics. ``improveResume`` additionally calls Apple
/// Intelligence's on-device system model (see `AppleIntelligenceResumeRewriter`) to rephrase
/// prose, when the hardware supports it — everything still runs on-device, no network access.
enum ResumeAnalysisEngine {
    static let isAvailable = true
    static let unavailableReason: String? = nil

    struct GrammarSuggestionItem {
        var title: String
        var detail: String
    }

    struct GrammarReview {
        var qualityScore: Int
        var suggestions: [GrammarSuggestionItem]
    }

    struct ImprovedResume {
        var improvedText: String
        var qualityScore: Int
        var suggestions: [GrammarSuggestionItem]
    }

    // MARK: - Spelling (the on-device system spell checker; no network, no model)

    /// A capitalized word the system dictionary doesn't recognize is, on a resume, almost always
    /// a proper noun — a person's name, a company, a tool, an acronym — not a typo. Resumes are
    /// unusually dense with these ("Figma", "PostgreSQL", "Kubernetes", "Jira", a surname), and
    /// the checker confidently offers a wrong "correction" for each one.
    ///
    /// Every capitalized word is skipped, including line-initial ones. An earlier version only
    /// skipped words that weren't first on their line — reasoning that sentence-initial capitals
    /// are grammatical rather than name-signalling — but that left a SKILLS line reading
    /// "Figma, User Research" flagged as a misspelling, which both produced a nonsense suggestion
    /// and silently docked 4 points off the score. Missing the rarer capitalized prose typo is a
    /// much smaller cost than mis-flagging every tool a candidate lists.
    private static func isLikelyProperNoun(_ word: String) -> Bool {
        word.first?.isUppercase == true
    }

    /// Whether the misspelled range sits inside an email address, URL, or number-bearing token
    /// (a phone number, a date range, a version string). The system checker has no concept of
    /// these — it sees "jane@example.com" and reports "example" or the whole local part as
    /// misspelled, which surfaces as the nonsense suggestion "Fix possible spelling issues —
    /// Flagged: jane@example.com". Resumes are full of such tokens in the contact header, so
    /// they're excluded from spell results entirely rather than flagged and never fixable.
    private static func isInsideNonProseToken(_ misspelledRange: NSRange, in text: NSString) -> Bool {
        // Expand to the surrounding run of non-whitespace characters, i.e. the whole "word" a
        // human would see, rather than the sub-fragment the checker happened to flag.
        var start = misspelledRange.location
        var end = misspelledRange.location + misspelledRange.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start > 0,
              let scalar = Unicode.Scalar(text.character(at: start - 1)),
              !whitespace.contains(scalar) {
            start -= 1
        }
        while end < text.length,
              let scalar = Unicode.Scalar(text.character(at: end)),
              !whitespace.contains(scalar) {
            end += 1
        }
        let token = text.substring(with: NSRange(location: start, length: end - start))
        if token.contains("@") || token.contains("://") || token.contains("www.") {
            return true
        }
        // Tokens carrying digits are identifiers, not prose: "4155550100", "2018-2021", "v2.1".
        return token.contains(where: \.isNumber)
    }

    static func spellingIssues(in text: String) -> [(word: String, suggestion: String?)] {
        #if os(iOS)
        let checker = UITextChecker()
        let nsText = text as NSString
        var results: [(String, String?)] = []
        var searchLocation = 0
        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let misspelledRange = checker.rangeOfMisspelledWord(
                in: text, range: searchRange, startingAt: searchLocation, wrap: false, language: "en"
            )
            guard misspelledRange.location != NSNotFound else { break }
            let word = nsText.substring(with: misspelledRange)
            searchLocation = misspelledRange.location + max(misspelledRange.length, 1)
            guard !isLikelyProperNoun(word) else { continue }
            guard !isInsideNonProseToken(misspelledRange, in: nsText) else { continue }
            let suggestion = checker.guesses(forWordRange: misspelledRange, in: text, language: "en")?.first
            results.append((word, suggestion))
        }
        return results
        #elseif os(macOS)
        // AppKit's equivalent of UITextChecker — same on-device, no-network system dictionary,
        // just a different API surface than iOS's.
        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        var results: [(String, String?)] = []
        var searchLocation = 0
        while searchLocation < nsText.length {
            let misspelledRange = checker.checkSpelling(of: text, startingAt: searchLocation)
            guard misspelledRange.location != NSNotFound else { break }
            let word = nsText.substring(with: misspelledRange)
            searchLocation = misspelledRange.location + max(misspelledRange.length, 1)
            guard !isLikelyProperNoun(word) else { continue }
            guard !isInsideNonProseToken(misspelledRange, in: nsText) else { continue }
            let suggestion = checker.guesses(forWordRange: misspelledRange, in: text, language: nil, inSpellDocumentWithTag: 0)?.first
            results.append((word, suggestion))
        }
        return results
        #else
        return []
        #endif
    }

    // MARK: - Lightweight grammar heuristics

    private static func repeatedWordMatches(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\w+)\s+\1\b"#, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range) }
    }

    /// Weak/passive bullet openers mapped to a stronger action-verb replacement — used both to
    /// flag issues and to actually fix them in ``improveResume``.
    private static let weakOpeners: [String: String] = [
        "responsible for": "Led", "was responsible for": "Led",
        "worked on": "Built", "helped with": "Contributed to",
        "in charge of": "Managed", "was in charge of": "Managed",
        "duties included": "Delivered", "tasked with": "Owned",
        "assisted with": "Supported", "involved in": "Drove"
    ]

    private static func bulletLines(in text: String) -> [String] {
        text.components(separatedBy: "\n").filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("•") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
        }
    }

    private static func weakOpenersFound(in text: String) -> [String] {
        let lowered = bulletLines(in: text).map { $0.lowercased() }
        return weakOpeners.keys.filter { phrase in lowered.contains { $0.contains(phrase) } }
    }

    private static func hasQuantifiableMetrics(_ text: String) -> Bool {
        text.contains("%") || text.contains(where: \.isNumber)
    }

    // MARK: - Quality scoring + suggestions

    static func reviewGrammar(resumeText: String) async throws -> GrammarReview {
        let spelling = spellingIssues(in: resumeText)
        let repeats = repeatedWordMatches(in: resumeText)
        let weak = weakOpenersFound(in: resumeText)
        let sections = ResumeSectionKit.detectedSections(in: resumeText)
        let expectedSections: Set<String> = ["Summary", "Experience", "Skills"]
        let missingSections = expectedSections.subtracting(sections)
        let hasMetrics = hasQuantifiableMetrics(resumeText)
        let bulletCount = bulletLines(in: resumeText).count
        let wordCount = resumeText.split { $0.isWhitespace || $0.isNewline }.count

        var score = 100
        score -= min(spelling.count * 4, 30)
        score -= min(repeats.count * 5, 15)
        score -= min(weak.count * 3, 15)
        if !hasMetrics { score -= 10 }
        if bulletCount == 0 { score -= 10 }
        score -= missingSections.count * 8
        if wordCount < 80 { score -= 10 }
        score = max(0, min(100, score))

        var suggestions: [GrammarSuggestionItem] = []
        if !spelling.isEmpty {
            let sample = spelling.prefix(3).map(\.word).joined(separator: ", ")
            suggestions.append(GrammarSuggestionItem(title: "Fix possible spelling issues", detail: "Flagged: \(sample)."))
        }
        if !repeats.isEmpty {
            suggestions.append(GrammarSuggestionItem(title: "Remove repeated words", detail: "Found repeated words like \"\(repeats[0])\"."))
        }
        if !weak.isEmpty {
            suggestions.append(GrammarSuggestionItem(title: "Strengthen weak bullet openers", detail: "Replace phrases like \"\(weak[0])\" with a strong action verb."))
        }
        if !hasMetrics {
            suggestions.append(GrammarSuggestionItem(title: "Add quantifiable metrics", detail: "Mention numbers or percentages to show measurable impact."))
        }
        if !missingSections.isEmpty {
            suggestions.append(GrammarSuggestionItem(title: "Add missing sections", detail: "Consider adding: \(missingSections.sorted().joined(separator: ", "))."))
        }
        if bulletCount == 0 {
            suggestions.append(GrammarSuggestionItem(title: "Use bullet points", detail: "Bulleted achievements are easier to scan than paragraphs."))
        }
        if wordCount < 80 {
            suggestions.append(GrammarSuggestionItem(title: "Add more detail", detail: "Your resume is quite short — add more about your experience and achievements."))
        }
        return GrammarReview(qualityScore: score, suggestions: Array(suggestions.prefix(4)))
    }

    /// The full `ResumeReview` (score + breakdown + suggestions) for the given text — shared by
    /// the initial upload-review screen and by re-scoring after "Fix It For Me" edits the text,
    /// so both stay computed by the exact same formula.
    static func buildReview(from text: String) async -> ResumeReview {
        let review = try? await reviewGrammar(resumeText: text)
        let overall = review?.qualityScore ?? 50
        let suggestions = review?.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) } ?? []

        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let hasDigits = text.contains { $0.isNumber }
        let hasBullets = text.contains("•") || text.contains("- ")
        let sections = ResumeSectionKit.detectedSections(in: text)
        let spellingCount = spellingIssues(in: text).count

        let formatting = hasBullets ? 82 : 60
        let contentImpact = hasDigits ? 80 : 62
        let grammar = max(40, min(98, 100 - spellingCount * 5))
        let ats = min(95, 55 + sections.count * 10 + min(wordCount / 40, 10))

        return ResumeReview(
            overallScore: overall,
            breakdown: [
                ResumeScoreBreakdown(title: "ATS Compatibility", percent: ats, icon: "checkmark.seal"),
                ResumeScoreBreakdown(title: "Content & Impact", percent: contentImpact, icon: "target"),
                ResumeScoreBreakdown(title: "Grammar & Clarity", percent: grammar, icon: "textformat.abc"),
                ResumeScoreBreakdown(title: "Formatting", percent: formatting, icon: "square.grid.2x2")
            ],
            suggestions: suggestions.isEmpty
                ? [ImprovementSuggestion(title: "Polish wording", detail: "Tighten a few sentences for extra clarity.")]
                : suggestions
        )
    }

    // MARK: - Rule-based improvement ("Fix It For Me")

    /// Applies deterministic, safe fixes only — spelling autocorrect (via the system's own top
    /// suggestion), weak-bullet-opener strengthening, and repeated-word/whitespace cleanup. There
    /// is no language model here to freely rewrite prose, so this can only ever tighten what's
    /// already there, never invent new content.
    private static func applySafeFixes(to resumeText: String) -> String {
        var improved = resumeText

        for (word, suggestion) in spellingIssues(in: resumeText) {
            guard let suggestion, suggestion.lowercased() != word.lowercased() else { continue }
            // Belt-and-braces: `spellingIssues` already filters capitalized words out via
            // `isLikelyProperNoun`, so nothing capitalized should reach here. Re-checking keeps
            // the "never silently rewrite a name" guarantee local to the code that does the
            // rewriting, so loosening the flagging filter later can't silently reintroduce
            // "Figma" → "Sigma" style corruption.
            guard !isLikelyProperNoun(word) else { continue }
            improved = replaceWholeWord(word, with: suggestion, in: improved)
        }

        for (phrase, replacement) in weakOpeners {
            improved = improved.replacingOccurrences(of: phrase, with: replacement, options: [.caseInsensitive])
        }

        improved = collapseRepeatedWords(improved)
        improved = improved.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        improved = normalizeBulletMarkers(improved)
        improved = capitalizeBulletStarts(improved)
        return improved
    }

    /// Suggestion titles that require inventing new content or restructuring the document — a
    /// phrasing-only rewrite (deterministic or the on-device model) can never satisfy these no
    /// matter how good it is, so their presence must never be treated as "AI might still help".
    private static let contentGapSuggestionTitles: Set<String> = [
        "Add quantifiable metrics", "Add missing sections", "Use bullet points", "Add more detail"
    ]

    /// Whether attempting a fix could actually change anything for this text, given what's
    /// currently wrong with it. Suggestions like "Add quantifiable metrics" or "Add missing
    /// sections" require inventing new content, which this engine deliberately never does — so
    /// callers should check this first and skip offering an auto-fix action when it's false,
    /// rather than let the user hit a "couldn't fix" failure with no path forward.
    static func hasAutoFixableIssues(in resumeText: String, suggestionTitles: [String]) -> Bool {
        if normalizedForComparison(applySafeFixes(to: resumeText)) != normalizedForComparison(resumeText) {
            return true
        }
        // Apple Intelligence (see AppleIntelligenceResumeRewriter) can still rephrase bullets or
        // a plain paragraph — but only when at least one *current* suggestion is actually a
        // phrasing issue. If every remaining suggestion is a content/structure gap, no rewrite
        // (AI or deterministic) can move the score, so claiming "fixable" here would just set up
        // the same guaranteed "Couldn't fix resume" failure this check exists to prevent.
        let hasPhrasingIssue = suggestionTitles.contains { !contentGapSuggestionTitles.contains($0) }
        return AppleIntelligenceResumeRewriter.isAvailable && hasPhrasingIssue
            && !resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Applies deterministic safe fixes plus, when Apple Intelligence is available, its rewrite —
    /// with no score-based accept/reject gating. Use this directly (instead of ``improveResume``)
    /// when `resumeText` is only a *fragment* of the document being scored elsewhere (e.g. just
    /// the work-history paragraph in the "write from scratch" flow) — a fragment's isolated score
    /// is never comparable to the whole document's score, so gating must happen at the call site
    /// against a rescore of the full assembled document, not here.
    static func applyFixes(to resumeText: String) async throws -> String {
        var improved = applySafeFixes(to: resumeText)
        if AppleIntelligenceResumeRewriter.isAvailable {
            improved = await applyOnDeviceBulletRewrite(to: improved)
        }
        guard normalizedForComparison(improved) != normalizedForComparison(resumeText) else {
            print("[ResumeAnalysisEngine] applyFixes: nothing safe to fix")
            throw ResumeAnalysisError.noImprovement
        }
        return improved
    }

    /// Convenience for callers where `resumeText` already represents the *whole* document being
    /// scored (e.g. the upload flow's full extracted text) — safe to gate on its own rescore here
    /// since there's no fragment/whole-document mismatch to worry about.
    static func improveResume(
        resumeText: String,
        suggestions: [GrammarSuggestionItem],
        currentScore: Int
    ) async throws -> ImprovedResume {
        let improved = try await applyFixes(to: resumeText)
        let review = try await reviewGrammar(resumeText: improved)
        // Not a strict ">" — some fixes (e.g. correcting one of several spelling errors when the
        // deduction is already capped) don't move the coarse heuristic score at all even though
        // they're genuine, safe improvements. Rejecting those as "failed" just because the score
        // didn't tick up would be wrong; only reject an actual regression.
        guard review.qualityScore >= currentScore else {
            print("[ResumeAnalysisEngine] improveResume: rewrite scored \(review.qualityScore), worse than \(currentScore) — discarding")
            throw ResumeAnalysisError.noImprovement
        }
        return ImprovedResume(improvedText: improved, qualityScore: review.qualityScore, suggestions: review.suggestions)
    }

    /// Runs bullet lines (or, for text with no bullets at all — e.g. the plain work-history
    /// paragraph in the "write from scratch" flow — the whole passage as one unit) through the
    /// on-device system model (see ``AppleIntelligenceResumeRewriter``) for punchier phrasing. By
    /// this point in ``applyFixes``, `applySafeFixes` has already normalized every bullet marker
    /// to "•", so that prefix reliably identifies bullet lines here. Anything the model fails to
    /// rewrite safely is left untouched.
    private static func applyOnDeviceBulletRewrite(to text: String) async -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("• ") }) else {
            guard let rewritten = try? await AppleIntelligenceResumeRewriter.shared.rewrite(passage: text) else {
                return text
            }
            return rewritten
        }
        var rewrittenLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("• ") else {
                rewrittenLines.append(line)
                continue
            }
            let leadingWhitespace = line.prefix(line.count - trimmed.count)
            let bulletBody = String(trimmed.dropFirst(2))
            if let rewritten = try? await AppleIntelligenceResumeRewriter.shared.rewrite(bulletLine: bulletBody) {
                rewrittenLines.append("\(leadingWhitespace)• \(rewritten)")
            } else {
                rewrittenLines.append(line)
            }
        }
        return rewrittenLines.joined(separator: "\n")
    }

    /// Normalizes "-"/"*" bullet markers to "•" for a consistent look — purely cosmetic (the
    /// scorer already recognizes all three as bullets), but still a real, visible improvement
    /// worth applying.
    private static func normalizeBulletMarkers(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingWhitespace = line.prefix(line.count - trimmed.count)
            if trimmed.hasPrefix("- ") {
                return leadingWhitespace + "• " + trimmed.dropFirst(2)
            }
            if trimmed.hasPrefix("* ") {
                return leadingWhitespace + "• " + trimmed.dropFirst(2)
            }
            return line
        }.joined(separator: "\n")
    }

    /// Capitalizes the first letter after a bullet marker — a common artifact of PDF text
    /// extraction losing the original capitalization.
    private static func capitalizeBulletStarts(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            guard let bulletRange = line.range(of: "• ") else { return line }
            let afterBullet = line[bulletRange.upperBound...]
            guard let firstChar = afterBullet.first, firstChar.isLowercase else { return line }
            return line[..<bulletRange.upperBound] + firstChar.uppercased() + afterBullet.dropFirst()
        }.joined(separator: "\n")
    }

    private static func replaceWholeWord(_ word: String, with replacement: String, in text: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func collapseRepeatedWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\w+)(\s+\1\b)+"#, options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func normalizedForComparison(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    // MARK: - Job title suggestions (curated skill → title mapping, fully offline)

    private static let jobTitlesBySkill: [String: [String]] = [
        "figma": ["Product Designer", "UX Designer"],
        "sketch": ["Product Designer", "UX Designer"],
        "user research": ["UX Researcher", "Product Designer"],
        "prototyping": ["Product Designer", "UX Designer"],
        "sql": ["Data Analyst", "Business Analyst"],
        "python": ["Data Analyst", "Backend Engineer", "ML Engineer"],
        "tensorflow": ["ML Engineer", "Data Scientist"],
        "pytorch": ["ML Engineer", "Data Scientist"],
        "swift": ["iOS Engineer", "Mobile Developer"],
        "swiftui": ["iOS Engineer", "Mobile Developer"],
        "kotlin": ["Android Engineer", "Mobile Developer"],
        "kubernetes": ["DevOps Engineer", "Platform Engineer"],
        "docker": ["DevOps Engineer", "Platform Engineer"],
        "terraform": ["DevOps Engineer", "Cloud Engineer"],
        "aws": ["Cloud Engineer", "DevOps Engineer"],
        "azure": ["Cloud Engineer", "DevOps Engineer"],
        "react": ["Frontend Engineer", "Full-Stack Engineer"],
        "node.js": ["Backend Engineer", "Full-Stack Engineer"],
        "project management": ["Project Manager", "Program Manager"],
        "scrum": ["Scrum Master", "Project Manager"],
        "salesforce": ["Salesforce Administrator", "CRM Analyst"],
        "excel": ["Business Analyst", "Data Analyst"],
        "tableau": ["Data Analyst", "BI Analyst"],
        "cybersecurity": ["Security Engineer", "SOC Analyst"]
    ]

    static func suggestFittingJobTitles(
        role: String,
        skills: [String],
        workHistory: String,
        resumeText: String?
    ) async throws -> [String] {
        let combinedText = ((resumeText ?? "") + " " + role + " " + workHistory).lowercased()
        var scored: [String: Int] = [:]
        for skill in skills {
            for title in jobTitlesBySkill[skill.lowercased()] ?? [] {
                scored[title, default: 0] += 2
            }
        }
        for (keyword, titles) in jobTitlesBySkill where combinedText.contains(keyword) {
            for title in titles { scored[title, default: 0] += 1 }
        }
        return Array(scored.sorted { $0.value > $1.value }.map(\.key).prefix(5))
    }

    // MARK: - Basic job-description matching

    /// Percentage overlap between the job description's top keywords and the resume's keywords
    /// — a simple, fully offline stand-in for semantic matching.
    static func matchJobDescription(resumeText: String, jobDescription: String) -> Int {
        guard !jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let jdKeywords = Set(ResumeSectionKit.extractKeywords(from: jobDescription, limit: 30))
        guard !jdKeywords.isEmpty else { return 0 }
        let resumeKeywords = Set(ResumeSectionKit.extractKeywords(from: resumeText, limit: 60))
        let overlap = jdKeywords.intersection(resumeKeywords)
        return Int((Double(overlap.count) / Double(jdKeywords.count)) * 100)
    }
}
