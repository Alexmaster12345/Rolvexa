import SwiftUI

struct ResumeReviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var isFixing = false
    @State private var fixProgress: Double = 0

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let fileName = appState.uploadedFileName {
                        HStack {
                            Image(systemName: "doc.fill").foregroundStyle(.red)
                            Text(fileName).font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.appCardBackground))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Resume Score")
                            .font(.title2.bold())
                        Text("Here's how it stacks up — and how to make it better")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let review = appState.resumeReview {
                        overallScoreCard(review)
                        breakdownSection(review)
                        suggestionsSection(review)
                    }

                    HStack(spacing: 12) {
                        Button("Upload Another") {
                            router.pop()
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                        .disabled(isFixing)

                        Button {
                            runFixItForMe()
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Fix it for me")
                            }
                        }
                        .buttonStyle(.primaryGradient)
                        .disabled(isFixing)
                    }
                }
                .padding(20)
            }

            if isFixing {
                FixingResumeOverlay(progress: fixProgress)
            }
        }
    }

    /// Runs the same deterministic + on-device-AI fix pipeline used elsewhere in the app (see
    /// `ResumeAnalysisEngine`) against the extracted resume text, showing `FixingResumeOverlay`
    /// for the duration. The progress bar is a simple animated approximation — the actual fix
    /// duration varies (longer if the bundled on-device model is available and engages), so this
    /// eases toward 90% and only jumps to 100% once the real work has actually finished.
    private func runFixItForMe() {
        guard !isFixing else { return }
        isFixing = true
        fixProgress = 0

        let progressTask = Task {
            while !Task.isCancelled, fixProgress < 0.9 {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation { fixProgress = min(fixProgress + 0.08, 0.9) }
            }
        }

        Task {
            defer { progressTask.cancel() }
            if let text = appState.extractedResumeText, !text.isEmpty,
               let improved = try? await ResumeAnalysisEngine.applyFixes(to: text) {
                appState.extractedResumeText = improved
                appState.extractedResumeDisplayText = improved
                appState.resumeReview = await ResumeAnalysisEngine.buildReview(from: improved)
                appState.aiReviewedThisSession = true
            }
            withAnimation { fixProgress = 1.0 }
            try? await Task.sleep(for: .milliseconds(250))
            isFixing = false
            router.push(.resumeTemplates)
        }
    }

    private func overallScoreCard(_ review: ResumeReview) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.indigo.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(review.overallScore) / 100)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(review.overallScore)%")
                    .font(.title3.bold())
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text("OVERALL SCORE")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Good — a few tweaks needed")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.yellow.opacity(0.25)))
                Text("\(review.suggestions.count) suggestions to boost your score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.indigo.opacity(0.06)))
    }

    private func breakdownSection(_ review: ResumeReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCORE BREAKDOWN")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(review.breakdown) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: item.icon)
                            .foregroundStyle(Color.indigo)
                            .frame(width: 20)
                        Text(item.title).font(.subheadline)
                        Spacer()
                        Text("\(item.percent)%").font(.subheadline.bold())
                    }
                    ProgressView(value: Double(item.percent), total: 100)
                        .tint(item.percent < 70 ? .orange : .indigo)
                }
            }
        }
    }

    private func suggestionsSection(_ review: ResumeReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOW TO IMPROVE")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(review.suggestions.count) suggestions")
                    .font(.caption.bold())
                    .foregroundStyle(Color.indigo)
            }

            ForEach(review.suggestions) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.subheadline.bold())
                        Text(suggestion.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.yellow.opacity(0.1)))
            }
        }
    }
}

#Preview {
    let state = AppState()
    state.uploadedFileName = "Jamie_Chen_Resume.pdf"
    state.resumeReview = ResumeReview(overallScore: 78, breakdown: [], suggestions: [])
    return NavigationStack {
        ResumeReviewView()
    }
    .environment(AppRouter())
    .environment(state)
}
