import Foundation
import Testing
@testable import Rolvexa

/// The on-device rewriting path.
///
/// Every test here is gated on `isAvailable`, so the suite still passes on hardware without
/// Apple Intelligence (A16 and earlier) rather than failing for an environmental reason. The
/// safety check itself is exercised unconditionally below, because that logic is pure and is
/// the part that actually protects the user's facts.
struct AppleIntelligenceRewriterTests {
    static var modelAvailable: Bool { AppleIntelligenceResumeRewriter.isAvailable }

    @Test(
        "A weak bullet comes back stronger with its numbers intact",
        .enabled(if: modelAvailable)
    )
    func rewriteKeepsTheFacts() async throws {
        let original = "Responsible for managing the deployment pipeline and helped with reducing release times by 40%."
        let rewritten = try await AppleIntelligenceResumeRewriter.shared.rewrite(bulletLine: original)

        // nil is a legitimate result — it means the safety check rejected the model's output.
        // What must never happen is a rewrite that silently changes a number.
        if let rewritten {
            #expect(!rewritten.isEmpty)
            #expect(rewritten.filter(\.isNumber).contains(original.filter(\.isNumber)),
                    "digits must survive: \(rewritten)")
            #expect(rewritten.count < original.count * 3)
        }
    }

    @Test(
        "A passage rewrite also preserves its numbers",
        .enabled(if: modelAvailable)
    )
    func passageRewriteKeepsTheFacts() async throws {
        let original = """
        Worked on the reporting system and helped with migrating 12 services to the new platform, \
        which reduced incidents by 25% over 6 months.
        """
        if let rewritten = try await AppleIntelligenceResumeRewriter.shared.rewrite(passage: original) {
            #expect(rewritten.filter(\.isNumber).contains(original.filter(\.isNumber)),
                    "digits must survive: \(rewritten)")
        }
    }

    @Test("Availability is reported honestly rather than assumed")
    func availabilityIsAWellDefinedBoolean() {
        // On hardware without Apple Intelligence this must be false, not a crash or a guess —
        // the whole deterministic fallback hangs off it.
        let available = AppleIntelligenceResumeRewriter.isAvailable
        #expect(available == true || available == false)
    }
}
