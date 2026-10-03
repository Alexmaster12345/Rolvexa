import Foundation

/// Compares a resume against a specific job description and explains the result.
///
/// Entirely deterministic — term matching and set arithmetic, no language model. A job-fit
/// number has to be defensible line by line ("you're missing Kubernetes and Terraform"), and a
/// generated percentage can't be audited by the person whose application depends on it.
///
/// Before this existed the UI showed a "Job Fit Score" that was really the resume *quality*
/// score, computed without ever reading a job description.
nonisolated enum JobFitAnalyzer {
    /// Weights per dimension. A dimension the posting says nothing about contributes nothing and
    /// its weight is redistributed across the rest — a job that lists no degree requirement
    /// shouldn't quietly dock someone for not having one.
    private enum Weight {
        static let skills = 50.0
        static let keywords = 25.0
        static let seniority = 15.0
        static let education = 10.0
    }

    private static let seniorityLevels = ["intern", "junior", "mid", "senior", "lead", "principal", "staff", "director"]
    private static let degreeTerms = ["bachelor", "master", "phd", "degree", "bsc", "msc", "b.s.", "m.s."]

    /// Words that appear in job postings because they're job postings, not because they describe
    /// the job. Matching these says nothing about whether someone can do the work.
    private static let postingBoilerplate: Set<String> = [
        "looking", "seeking", "candidate", "candidates", "applicant", "applicants", "successful",
        "ideal", "opportunity", "position", "vacancy", "apply", "application", "join", "hiring",
        "required", "requirement", "requirements", "essential", "desirable", "preferred", "must",
        "should", "ability", "able", "strong", "excellent", "proven", "track", "record",
        "across", "within", "using", "various", "well", "also", "help", "need", "needs",
        "today", "currently", "ensure", "ensuring", "support", "supporting", "partner",
        "company", "companies", "business", "organisation", "organization", "department",
        "benefits", "salary", "competitive", "offer", "offers", "contract", "permanent",
        "full-time", "part-time", "remote", "hybrid", "onsite", "office", "location"
    ]

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var start = haystack.startIndex
        while let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }

    /// Returns nil when there's no job description to compare against — the caller must then
    /// avoid presenting any kind of match figure.
    static func analyze(jobDescription: String, resumeText: String, resumeSkills: [String]) -> JobFitAnalysis? {
        let posting = jobDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard posting.count >= 40 else { return nil }

        let postingLower = posting.lowercased()
        // The resume's own skill list is matched alongside the body text: a skill can be listed
        // in the Skills section without the word appearing in any bullet.
        let resumeHaystack = (resumeText + "\n" + resumeSkills.joined(separator: "\n")).lowercased()

        // MARK: Hard skills

        let requiredSkills = ResumeSectionKit.knownSkillKeywords.filter { contains($0, in: postingLower) }
        let matchedSkills = requiredSkills.filter { contains($0, in: resumeHaystack) }
        let missingSkills = requiredSkills.filter { !contains($0, in: resumeHaystack) }

        // MARK: Softer keywords

        // Terms the posting leans on that aren't in the skill vocabulary — domain words like
        // "compliance" or "stakeholder".
        //
        // Filtered hard, because this is the one dimension that can punish a candidate for
        // vocabulary rather than ability. Skills and degree/seniority words are excluded (they
        // are scored on their own axis, and counting them here charged twice for one gap), and a
        // term must appear at least twice to count as a theme — a single "today" or "looking"
        // otherwise dragged a 100%-skills-match down to 73%.
        let requiredSkillsLower = Set(requiredSkills.map { $0.lowercased() })
        let keywords = ResumeSectionKit.extractKeywords(from: posting, limit: 25)
            .filter { candidate in
                !requiredSkillsLower.contains(candidate)
                    && !postingBoilerplate.contains(candidate)
                    && !degreeTerms.contains(candidate)
                    && !seniorityLevels.contains(candidate)
                    && occurrences(of: candidate, in: postingLower) >= 2
            }
            .prefix(10)
            .map { $0 }
        let matchedKeywords = keywords.filter { contains($0, in: resumeHaystack) }
        let missingKeywords = keywords.filter { !contains($0, in: resumeHaystack) }

        // MARK: Seniority

        let postingLevels = seniorityLevels.filter { contains($0, in: postingLower) }
        let resumeLevels = seniorityLevels.filter { contains($0, in: resumeHaystack) }
        let seniorityMatches = !postingLevels.isEmpty && !Set(postingLevels).isDisjoint(with: Set(resumeLevels))

        // MARK: Education

        let postingWantsDegree = degreeTerms.contains { contains($0, in: postingLower) }
        let resumeHasDegree = ResumeSectionKit.detectedSections(in: resumeText).contains("Education")
            || degreeTerms.contains { contains($0, in: resumeHaystack) }

        // MARK: Scoring

        var components: [JobFitComponent] = []
        var earned = 0.0
        var available = 0.0

        if !requiredSkills.isEmpty {
            let ratio = Double(matchedSkills.count) / Double(requiredSkills.count)
            earned += ratio * Weight.skills
            available += Weight.skills
            components.append(JobFitComponent(
                title: "Technical Skills",
                percent: Int((ratio * 100).rounded()),
                detail: "\(matchedSkills.count) of \(requiredSkills.count) listed skills found"
            ))
        }
        // Below a handful of surviving terms there isn't a theme to measure, only noise — so the
        // dimension is dropped and its weight goes to the others rather than scoring randomness.
        if keywords.count >= 3 {
            let ratio = Double(matchedKeywords.count) / Double(keywords.count)
            earned += ratio * Weight.keywords
            available += Weight.keywords
            components.append(JobFitComponent(
                title: "Keywords",
                percent: Int((ratio * 100).rounded()),
                detail: "\(matchedKeywords.count) of \(keywords.count) recurring terms covered"
            ))
        }
        if !postingLevels.isEmpty {
            earned += (seniorityMatches ? 1 : 0) * Weight.seniority
            available += Weight.seniority
            components.append(JobFitComponent(
                title: "Seniority",
                percent: seniorityMatches ? 100 : 0,
                detail: seniorityMatches
                    ? "Your level matches the posting"
                    : "Posting asks for: \(postingLevels.joined(separator: ", "))"
            ))
        }
        if postingWantsDegree {
            earned += (resumeHasDegree ? 1 : 0) * Weight.education
            available += Weight.education
            components.append(JobFitComponent(
                title: "Education",
                percent: resumeHasDegree ? 100 : 0,
                detail: resumeHasDegree ? "Degree listed" : "Posting asks for a degree; none found"
            ))
        }

        // A posting so sparse that nothing could be extracted isn't a 0% match, it's unanalysable.
        guard available > 0 else { return nil }

        // Recurring words alone aren't evidence that this is a job posting — pasted gibberish
        // produced a confident "0% — Weak match" off nothing but its own repeated nonsense.
        // Require at least one concrete requirement before reporting any figure.
        guard !requiredSkills.isEmpty || !postingLevels.isEmpty || postingWantsDegree else { return nil }

        return JobFitAnalysis(
            overallScore: Int(((earned / available) * 100).rounded()),
            components: components,
            matchedSkills: matchedSkills,
            missingSkills: missingSkills,
            matchedKeywords: matchedKeywords,
            missingKeywords: missingKeywords
        )
    }

    /// Characters that continue a technology name rather than ending it.
    ///
    /// Alphanumerics plus `+` and `#`, so "C" doesn't match inside "C++" or "C#" — otherwise a
    /// posting asking for C++ registered a requirement for C as well, and the resume's own "C++"
    /// then satisfied both, inflating the match. `.` and `/` are deliberately excluded: they end
    /// sentences and separate words far more often than they appear mid-token, and treating them
    /// as continuations would stop "AWS" matching "…deployed on AWS."
    private static func continuesToken(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "+" || character == "#"
    }

    /// Whole-term containment.
    ///
    /// A plain `contains` would match "R" inside "Paris" and "Go" inside "Google", so each edge
    /// of the term must sit against a token boundary — but only where that edge is itself
    /// part of a token, so "C++", "CI/CD" and "Node.js" still match their own punctuation.
    private static func contains(_ term: String, in haystack: String) -> Bool {
        let needle = term.lowercased()
        guard !needle.isEmpty else { return false }
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
}
