import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// Runs a small, bundled on-device language model (Llama-3.2-1B-Instruct, 4-bit — ships inside
/// the app bundle at `Resources/ResumeRewriteModel/`, no network, no Hugging Face download at
/// runtime) to rewrite individual resume bullet lines for punchier phrasing. This sits alongside
/// — not instead of — the deterministic fixes in `ResumeAnalysisEngine`: word-swaps can never
/// hallucinate, a language model occasionally can, so every rewrite is checked in
/// `isSafeRewrite` before being accepted.
actor OnDeviceResumeRewriter {
    static let shared = OnDeviceResumeRewriter()

    /// Xcode's file-system-synchronized group copies this folder's contents into the app bundle
    /// flattened (siblings of Info.plist), not as a `ResumeRewriteModel/` subdirectory — so at
    /// runtime these are located individually and symlinked back into a real directory, since
    /// `LLMModelFactory` needs them all sitting together on disk.
    private static let modelFilenames = [
        "config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "special_tokens_map.json",
        "tokenizer.json",
        "tokenizer_config.json",
    ]

    /// Whether the model files are present in the app bundle. Doesn't guarantee the device can
    /// actually load them (that's discovered lazily, on first real use).
    static var isBundled: Bool {
        modelFilenames.allSatisfy {
            FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent($0).path)
        }
    }

    private var containerTask: Task<ModelContainer, Error>?

    private func loadedContainer() async throws -> ModelContainer {
        if let containerTask { return try await containerTask.value }
        let task = Task<ModelContainer, Error> {
            let modelDirectory = try Self.materializedModelDirectory()
            return try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
        }
        containerTask = task
        return try await task.value
    }

    /// Symlinks the flattened bundle files into a real `ResumeRewriteModel/` directory under
    /// Caches, once — cheap enough to redo every launch (no bytes are copied, just links), so
    /// there's no harm if the OS purges Caches under storage pressure.
    private static func materializedModelDirectory() throws -> URL {
        let destDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ResumeRewriteModel", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        for filename in modelFilenames {
            let source = Bundle.main.bundleURL.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw OnDeviceResumeRewriterError.modelNotBundled
            }
            let dest = destDir.appendingPathComponent(filename)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: source)
        }
        return destDir
    }

    /// Rewrites one bullet line. Returns `nil` (never throws for content reasons) if the model's
    /// output fails the safety check — a resume is the one place a silently "improved" but
    /// fabricated line is worse than leaving the original untouched.
    func rewrite(bulletLine: String) async throws -> String? {
        try await performRewrite(
            text: bulletLine,
            instructions: """
            You rewrite a single resume bullet point to be punchier. Rules:
            - Keep the exact same facts, numbers, tools, and scope. Never invent new numbers, \
            tools, or achievements that aren't already in the text you're given.
            - Start with a strong past-tense action verb.
            - Keep it one line, no more than about 20 words.
            - Reply with ONLY the rewritten bullet text — no quotes, no explanation, no bullet marker.
            """,
            maxTokens: 60
        )
    }

    /// Rewrites a whole plain-text passage (e.g. the "write from scratch" work-history paragraph,
    /// which has no bullet markers to split on) as a single unit, rather than doing nothing just
    /// because there's no bullet structure to operate on line-by-line.
    func rewrite(passage: String) async throws -> String? {
        try await performRewrite(
            text: passage,
            instructions: """
            You rewrite a short resume work-history paragraph to be punchier. Rules:
            - Keep the exact same facts, numbers, tools, and scope. Never invent new numbers, \
            tools, or achievements that aren't already in the text you're given.
            - Use strong past-tense action verbs instead of weak phrasing like "worked on" or \
            "helped with".
            - Keep roughly the same length as the original.
            - Reply with ONLY the rewritten paragraph — no quotes, no explanation.
            """,
            maxTokens: 200
        )
    }

    private func performRewrite(text: String, instructions: String, maxTokens: Int) async throws -> String? {
        let container = try await loadedContainer()
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        )
        let raw = try await session.respond(to: text)
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard isSafeRewrite(original: text, rewritten: cleaned) else { return nil }
        return cleaned
    }

    /// Every digit that appeared in the original must survive, in the same order — the model is
    /// explicitly told never to touch numbers, so any change here means it drifted from fact.
    private func isSafeRewrite(original: String, rewritten: String) -> Bool {
        guard !rewritten.isEmpty, rewritten.count < original.count * 3 else { return false }
        let originalDigits = original.filter(\.isNumber)
        guard !originalDigits.isEmpty else { return true }
        return rewritten.filter(\.isNumber).contains(originalDigits)
    }
}

enum OnDeviceResumeRewriterError: Error {
    case modelNotBundled
}
