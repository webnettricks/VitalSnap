import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}
