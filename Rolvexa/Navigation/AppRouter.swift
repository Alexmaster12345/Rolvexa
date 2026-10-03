import SwiftUI
import Observation

enum AppRoute: Hashable {
    case resumeUpload
    case resumeReview
    case inputExperience
    case resumeTemplates
    case aiBuilding
    case resumeKit
    case reviewAndApply
    case legalAndPrivacy
    case legalDocument(LegalDocument)
}

@Observable
final class AppRouter {
    var path = NavigationPath()

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
