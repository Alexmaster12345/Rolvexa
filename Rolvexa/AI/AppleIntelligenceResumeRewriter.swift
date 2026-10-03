import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rewrites resume prose using Apple Intelligence's on-device system model (via the
/// `FoundationModels` framework) for punchier phrasing. Nothing is bundled and nothing is
/// downloaded — the model ships with the OS — and no request ever leaves the device.
///
/// This sits alongside — not instead of — the deterministic fixes in `ResumeAnalysisEngine`:
/// word-swaps can never hallucinate, a language model occasionally can, so every rewrite is
/// still checked by `isSafeRewrite` before being accepted. Guided generation (`@Generable`)
/// guarantees the *shape* of the response, not its factual fidelity.
///
/// Availability is not guaranteed: Apple Intelligence requires capable hardware (A17 Pro or
/// newer) and an eligible region, so callers must check ``isAvailable`` and fall back to the
/// deterministic-only path when it's false.
actor AppleIntelligenceResumeRewriter {
    static let shared = AppleIntelligenceResumeRewriter()

    /// Whether the on-device system model can be used right now. False on hardware that doesn't
    /// support Apple Intelligence, when the user hasn't enabled it, or while model assets are
    /// still downloading.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    /// The shape of a rewrite. Using guided generation instead of parsing free-form text means
    /// the model can't return a preamble, an apology, or a markdown fence that then has to be
    /// stripped back off — the framework constrains sampling so the result is always this type.
    @available(iOS 26, macOS 26, *)
    @Generable(description: "A rewritten piece of resume text")
    struct Rewrite {
        @Guide(description: "The rewritten text, with the same facts, numbers, and scope as the original")
        var text: String
    }

    @available(iOS 26, macOS 26, *)
    private func session(instructions: String) -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
    }
    #endif

    /// Rewrites one bullet line. Returns `nil` (rather than throwing) when the model's output
    /// fails the safety check — a resume is the one place a silently "improved" but fabricated
    /// line is worse than leaving the original untouched.
    func rewrite(bulletLine: String) async throws -> String? {
        try await performRewrite(
            text: bulletLine,
            instructions: """
            Rewrite the user's resume bullet point so it reads more strongly.

            Start with a past-tense action verb. Keep it to one line of at most 20 words.

            Output only the rewritten bullet itself. Do not restate these instructions, do not \
            add commentary about what you changed, and do not introduce any fact, number, tool, \
            or achievement that is not already present in the user's text.
            """,
            maximumResponseTokens: 100
        )
    }

    /// Rewrites a whole plain-text passage (e.g. the "write from scratch" work-history
    /// paragraph, which has no bullet markers to split on) as a single unit.
    func rewrite(passage: String) async throws -> String? {
        try await performRewrite(
            text: passage,
            instructions: """
            Rewrite the user's resume work-history paragraph so it reads more strongly.

            Replace weak phrasing such as "worked on" or "helped with" with past-tense action \
            verbs. Keep roughly the same length as the original.

            Output only the rewritten paragraph itself. Do not restate these instructions, do \
            not add commentary about what you changed, and do not introduce any fact, number, \
            tool, or achievement that is not already present in the user's text.
            """,
            maximumResponseTokens: 400
        )
    }

    private func performRewrite(
        text: String,
        instructions: String,
        maximumResponseTokens: Int
    ) async throws -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else { return nil }
        guard Self.isAvailable else { return nil }

        let session = session(instructions: instructions)
        var options = GenerationOptions()
        options.maximumResponseTokens = maximumResponseTokens

        let response = try await session.respond(
            to: text,
            generating: Rewrite.self,
            options: options
        )
        let cleaned = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeRewrite(original: text, rewritten: cleaned) else { return nil }
        return cleaned
        #else
        return nil
        #endif
    }

    /// Every digit that appeared in the original must survive, in the same order — the model is
    /// explicitly told never to touch numbers, so any change here means it drifted from fact.
    ///
    /// Internal rather than private so tests can exercise it directly. This is the gate that
    /// actually protects the user's facts, and it's pure — testing it through the model would
    /// make the guarantee only as reliable as the model's availability on the test machine.
    func isSafeRewrite(original: String, rewritten: String) -> Bool {
        guard !rewritten.isEmpty, rewritten.count < original.count * 3 else { return false }
        // Compared as whole numbers in order, not as a digit substring. Flattening to digits and
        // asking whether the rewrite *contains* them accepted "3 sites" becoming "30 sites" —
        // "4030" contains "403" — so a model could multiply a figure tenfold and pass the check.
        // Requiring the exact sequence also rejects a number being invented or dropped.
        guard numbers(in: rewritten) == numbers(in: original) else { return false }
        guard introducesNoNewNouns(original: original, rewritten: rewritten) else { return false }
        return doesNotEscalateOwnership(original: original, rewritten: rewritten)
    }

    /// Each run of digits as its own token: "40% over 3 months" → ["40", "3"].
    private func numbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }

    // MARK: - Beyond numbers

    /// Verbs and nouns that assert ownership, authorship or seniority.
    ///
    /// Checking numbers alone can't see the most plausible kind of drift: "Worked with Nvidia
    /// GPUs" becoming "Designed Nvidia GPU infrastructure" changes no digit but promotes the
    /// candidate from user to author. On a resume that is a lie with consequences.
    /// Only unambiguous verb forms — past tense and present participle.
    ///
    /// The bare stems are deliberately absent. Including "design" made "Contributed to the
    /// design review" look like it already claimed ownership, which then permitted "Architected
    /// the design review". The same trap waits in "build pipeline", "team lead" and "product
    /// owner": all nouns. The `-s` forms are omitted for the same reason ("the leads", "the
    /// builds"), and cost nothing, since resume bullets are written in past tense.
    private static let ownershipTerms: Set<String> = [
        "led", "leading", "managed", "managing", "owned", "owning",
        "designed", "designing", "architected", "architecting",
        "built", "building", "created", "creating", "founded", "founding",
        "headed", "heading", "directed", "directing",
        "spearheaded", "pioneered", "invented", "established",
        "drove", "driving", "oversaw", "overseeing", "launched", "launching",
        "supervised", "supervising", "mentored", "mentoring",
        // "Worked on the billing system" → "Developed the billing system" passed the first
        // version of this list: authorship verbs are the same promotion as leadership verbs.
        "developed", "developing", "engineered", "authored", "devised", "orchestrated",
        "transformed", "revamped", "overhauled", "rearchitected", "championed",
        "initiated", "originated"
    ]

    /// A rewrite may not claim more ownership than the original did.
    ///
    /// Lenient in one direction on purpose: once the original asserts ownership anywhere, the
    /// rewrite is free to reword it ("responsible for managing" → "led"), because the claim was
    /// already made. What it cannot do is introduce ownership into a sentence that had none.
    private func doesNotEscalateOwnership(original: String, rewritten: String) -> Bool {
        let originalClaims = !Self.ownershipTerms.isDisjoint(with: significantTerms(in: original))
        if originalClaims { return true }
        return Self.ownershipTerms.isDisjoint(with: significantTerms(in: rewritten))
    }

    /// Words a rewrite is allowed to introduce: connectives and neutral verbs that restate
    /// rather than upgrade. Anything else new is treated as invented content.
    private static let permittedAdditions: Set<String> = [
        "and", "the", "for", "with", "that", "this", "from", "into", "across", "through",
        "while", "which", "their", "its", "our", "was", "were", "has", "had", "have",
        "than", "then", "also", "both", "each", "more", "over", "under", "using", "used",
        "including", "well", "all", "new", "per", "via", "plus",
        // Neutral restatements of effort, no stronger than the original.
        "worked", "working", "works", "helped", "helping", "helps", "supported",
        "supporting", "supports", "contributed", "contributing", "assisted", "assisting",
        "handled", "handling", "performed", "performing", "completed", "completing",
        "maintained", "maintaining", "delivered", "delivering", "reduced", "reducing",
        "improved", "improving", "increased", "increasing", "cut", "cutting",
        "negotiated", "negotiating", "implemented", "implementing", "coordinated",
        "coordinating", "standardised", "standardized", "introduced", "introducing",
        "scheduled", "scheduling", "audited", "auditing", "trained", "training"
    ]

    /// The rewrite may not introduce a company, technology, certification or other content noun
    /// that the original never mentioned.
    ///
    /// Guards the second half of the hallucination problem: a model asked to make a bullet
    /// "stronger" will happily add "enterprise", "Kubernetes" or a team size that was never
    /// there. Judged on significant terms only, so punctuation and articles don't trip it.
    private func introducesNoNewNouns(original: String, rewritten: String) -> Bool {
        let before = significantTerms(in: original)
        let introduced = significantTerms(in: rewritten)
            .subtracting(before)
            .subtracting(Self.permittedAdditions)
            .subtracting(Self.ownershipTerms)   // handled separately, with its own rule

        // A known technology name is never an acceptable addition: it's a claim about what the
        // candidate has used, which only they can make.
        let inventedSkill = introduced.contains { term in
            ResumeSectionKit.knownSkillKeywords.contains { $0.lowercased() == term }
        }
        if inventedSkill { return false }

        // Otherwise allow a small amount of connective rewording, but not whole new clauses.
        return introduced.count <= 2
    }

    /// Lowercased word-ish tokens of three or more characters.
    private func significantTerms(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }
}
