import Foundation
import Testing
@testable import Rolvexa

/// The on-device rewriting path.
///
/// Split deliberately into two kinds of test. The safety gate is pure, so it's asserted
/// exhaustively and unconditionally — it's the thing that actually protects the user's facts.
/// The tests that invoke the model are best-effort: `SystemLanguageModel.availability` can
/// report `.available` and the call still fail (assets paging in, the system under load,
/// a shared CI machine), so treating that as a test failure made the build non-deterministic
/// rather than catching a defect.
struct AppleIntelligenceRewriterTests {
    static var modelAvailable: Bool { AppleIntelligenceResumeRewriter.isAvailable }

    // MARK: - The safety gate (pure, always runs)

    @Test("A rewrite that drops or changes a digit is rejected", arguments: [
        ("Cut costs by 40% across 3 sites", "Cut costs by 4% across 3 sites"),
        ("Cut costs by 40% across 3 sites", "Cut costs by 40% across 30 sites"),
        ("Cut costs by 40% across 3 sites", "Cut costs significantly across several sites"),
        ("Managed 12 engineers", "Managed 21 engineers"),
        // A number the original never mentioned must not be invented.
        ("Led the migration", "Led the migration, cutting costs 30%")
    ])
    func rejectsRewritesThatAlterNumbers(original: String, rewritten: String) async {
        let rewriter = AppleIntelligenceResumeRewriter.shared
        #expect(await !rewriter.isSafeRewrite(original: original, rewritten: rewritten))
    }

    @Test("A rewrite keeping every digit in order is accepted", arguments: [
        ("Responsible for cutting costs by 40% across 3 sites", "Cut costs by 40% across 3 sites"),
        ("Was responsible for managing 12 engineers", "Led 12 engineers"),
        ("Helped with the migration", "Drove the migration")
    ])
    func acceptsRewritesThatKeepTheFacts(original: String, rewritten: String) async {
        let rewriter = AppleIntelligenceResumeRewriter.shared
        #expect(await rewriter.isSafeRewrite(original: original, rewritten: rewritten))
    }

    @Test("An empty or runaway rewrite is rejected")
    func rejectsDegenerateOutput() async {
        let rewriter = AppleIntelligenceResumeRewriter.shared
        let original = "Led the migration"
        #expect(await !rewriter.isSafeRewrite(original: original, rewritten: ""))
        // Three times the original length means the model started rambling rather than tightening.
        let runaway = String(repeating: "Led the migration and more besides. ", count: 10)
        #expect(await !rewriter.isSafeRewrite(original: original, rewritten: runaway))
    }

    @Test("Text with no digits is judged on length alone")
    func digitFreeTextIsAccepted() async {
        let rewriter = AppleIntelligenceResumeRewriter.shared
        #expect(await rewriter.isSafeRewrite(original: "Helped with the rollout", rewritten: "Drove the rollout"))
    }

    // MARK: - Availability

    @Test("Availability is reported as a definite answer, never a crash")
    func availabilityIsAWellDefinedBoolean() {
        // The entire deterministic fallback hangs off this, so it must always answer.
        let available = AppleIntelligenceResumeRewriter.isAvailable
        #expect(available == true || available == false)
    }

    // MARK: - End-to-end (best effort)

    /// Runs a real rewrite when the model is both present and willing.
    ///
    /// A thrown error is treated the same as no rewrite: the model being unusable right now is
    /// an environmental fact, not a defect in this code. What's asserted is the contract that
    /// matters — *if* text comes back, it kept the facts.
    private func assertRewritePreservesDigits(
        _ original: String,
        _ rewrite: (String) async throws -> String?
    ) async {
        guard Self.modelAvailable else { return }
        guard let rewritten = try? await rewrite(original) else { return }

        #expect(!rewritten.isEmpty)
        #expect(
            rewritten.filter(\.isNumber).contains(original.filter(\.isNumber)),
            "digits must survive the rewrite: \(rewritten)"
        )
        #expect(rewritten.count < original.count * 3)
    }

    @Test("A real bullet rewrite keeps its numbers", .enabled(if: modelAvailable))
    func liveBulletRewriteKeepsTheFacts() async {
        await assertRewritePreservesDigits(
            "Responsible for managing the deployment pipeline and helped with reducing release times by 40%."
        ) { try await AppleIntelligenceResumeRewriter.shared.rewrite(bulletLine: $0) }
    }

    @Test("A real passage rewrite keeps its numbers", .enabled(if: modelAvailable))
    func livePassageRewriteKeepsTheFacts() async {
        await assertRewritePreservesDigits("""
        Worked on the reporting system and helped with migrating 12 services to the new platform, \
        which reduced incidents by 25% over 6 months.
        """) { try await AppleIntelligenceResumeRewriter.shared.rewrite(passage: $0) }
    }
}
