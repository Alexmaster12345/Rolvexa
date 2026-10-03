import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var router = AppRouter()
    @State private var appState = AppState()

    var body: some View {
        Group {
            if showSplash {
                SplashView {
                    withAnimation {
                        showSplash = false
                    }
                }
            } else {
                NavigationStack(path: $router.path) {
                    OnboardingView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
        .environment(router)
        .environment(appState)
        // No silent restore on launch. The draft is still saved on the way out, but reopening it
        // is now an explicit choice on the onboarding screen ("Open saved resume"), so starting
        // a fresh upload doesn't begin half-filled with the last session's answers.
        .onChange(of: scenePhase) { _, phase in
            // Saved on the way out rather than per keystroke: a resume is sensitive enough that
            // it shouldn't be rewritten to disk on every character, and leaving the foreground
            // is the point at which the process might not come back.
            if phase != .active {
                appState.saveDraft()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .resumeUpload:
            ResumeUploadView()
        case .resumeReview:
            ResumeReviewView()
        case .inputExperience:
            InputExperienceView()
        case .resumeTemplates:
            ResumeTemplatesView()
        case .aiBuilding:
            AIBuildingView()
        case .resumeKit:
            ResumeKitView()
        case .reviewAndApply:
            ReviewAndApplyView()
        case .legalAndPrivacy:
            LegalAndPrivacyView()
        case .legalDocument(let document):
            LegalDocumentView(document: document)
        }
    }
}

#Preview {
    ContentView()
}
