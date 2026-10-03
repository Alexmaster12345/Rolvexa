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
        return numbers(in: rewritten) == numbers(in: original)
    }

    /// Each run of digits as its own token: "40% over 3 months" → ["40", "3"].
    private func numbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }
}
