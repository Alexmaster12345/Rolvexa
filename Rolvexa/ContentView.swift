import SwiftUI

struct ContentView: View {
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
        }
    }
}

#Preview {
    ContentView()
}
