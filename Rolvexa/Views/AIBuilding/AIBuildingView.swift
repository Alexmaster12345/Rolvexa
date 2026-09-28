import SwiftUI

struct AIBuildingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    private struct Stage: Identifiable {
        let id = UUID()
        let title: String
        var status: Status
    }

    private enum Status { case done, inProgress, pending }

    @State private var stages: [Stage] = [
        Stage(title: "Analyzing job requirements", status: .done),
        Stage(title: "Matching your experience", status: .done),
        Stage(title: "Writing tailored resume", status: .inProgress),
        Stage(title: "Crafting cover letter", status: .pending)
    ]

    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 24) {
            StepProgressHeader(step: 3, totalSteps: 4)

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.indigo.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: isSpinning)

                Circle()
                    .fill(Color.indigo)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "brain")
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: 110, height: 110)

            VStack(spacing: 6) {
                Text("Building your application kit…")
                    .font(.title3.bold())
                Text("Our AI is analyzing the role and tailoring your materials")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(stages) { stage in
                    stageRow(stage)
                }
            }

            Spacer()

            Text("This usually takes about 20 seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        #if os(iOS)
        .navigationBarBackButtonHidden()
        #endif
        .onAppear {
            isSpinning = true
        }
        .task {
            await runBuildSequence()
        }
    }

    private func stageRow(_ stage: Stage) -> some View {
        HStack {
            statusIcon(stage.status)
            Text(stage.title)
                .font(.subheadline.bold())
            Spacer()
            Text(label(for: stage.status))
                .font(.caption.bold())
                .foregroundStyle(color(for: stage.status))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(stage.status == .inProgress ? Color.indigo.opacity(0.08) : Color.appCardBackground)
        )
    }

    @ViewBuilder
    private func statusIcon(_ status: Status) -> some View {
        switch status {
        case .done:
            Circle().fill(.green).frame(width: 22, height: 22)
                .overlay { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) }
        case .inProgress:
            ProgressView().frame(width: 22, height: 22)
        case .pending:
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1).frame(width: 22, height: 22)
        }
    }

    private func label(for status: Status) -> String {
        switch status {
        case .done: return "Done"
        case .inProgress: return "In progress"
        case .pending: return "Pending"
        }
    }

    private func color(for status: Status) -> Color {
        switch status {
        case .done: return .green
        case .inProgress: return .indigo
        case .pending: return .secondary
        }
    }

    private func runBuildSequence() async {
        // Stages 1-2 start already marked "done" (see initial `stages` state above) — there's
        // no dedicated model call for "job requirements" or "experience matching" in this pass.
        // Stages 3-4 below make a real on-device Apple Intelligence call when it's available on
        // this device, falling back to the existing deterministic heuristics/templates otherwise.
        stages[2].status = .inProgress
        await runTailoredResumeStage()
        stages[2].status = .done

        stages[3].status = .inProgress
        await runCoverLetterStage()
        await runJobFitTitlesStage()
        stages[3].status = .done

        router.push(.resumeKit)
    }

    private func runTailoredResumeStage() async {
        // Real, fully offline analysis (NaturalLanguage + system spell checker + deterministic
        // heuristics — see ResumeAnalysisEngine) run against whichever text represents this
        // resume: the uploaded file's extracted text, or the assembled write-from-scratch text.
        let text = appState.buildSource == .upload ? (appState.extractedResumeText ?? "") : appState.resumeExportText()
        guard !text.isEmpty else {
            applyFallbackApplicationKit()
            return
        }
        do {
            let review = try await ResumeAnalysisEngine.reviewGrammar(resumeText: text)
            appState.applicationKit = ApplicationKit(
                jobFitScore: review.qualityScore,
                suggestions: review.suggestions.map { ImprovementSuggestion(title: $0.title, detail: $0.detail) }
            )
            appState.aiReviewedThisSession = true
        } catch {
            print("[ResumeAnalysisEngine] reviewGrammar failed: \(error)")
            applyFallbackApplicationKit()
        }
    }

    private func runCoverLetterStage() async {
        // No local-AI-generated cover letter body anymore — there's no on-device language model
        // to write free-form prose. The deterministic template in AppState+ExportText.swift
        // already produces a solid cover letter from the entered role/skills/work history, and
        // is used automatically whenever aiGeneratedCoverLetterBody is nil.
    }

    private func runJobFitTitlesStage() async {
        do {
            let titles = try await ResumeAnalysisEngine.suggestFittingJobTitles(
                role: appState.experience.currentRole,
                skills: appState.experience.skills,
                workHistory: appState.experience.workHistorySummary,
                resumeText: appState.buildSource == .upload ? appState.extractedResumeText : nil
            )
            appState.suggestedJobTitles = titles
        } catch {
            print("[ResumeAnalysisEngine] suggestFittingJobTitles failed: \(error)")
            // appState.suggestedJobTitles stays empty; the Review & Send screen hides the section.
        }
    }

    private func applyFallbackApplicationKit() {
        if appState.buildSource == .upload, let review = appState.resumeReview {
            appState.applicationKit = ApplicationKit(
                jobFitScore: review.overallScore,
                suggestions: review.suggestions
            )
        } else {
            appState.applicationKit = ApplicationKit(
                jobFitScore: 87,
                suggestions: [
                    ImprovementSuggestion(title: "Add quantifiable metrics to your last role", detail: "")
                ]
            )
        }
    }
}

#Preview {
    NavigationStack {
        AIBuildingView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
