import SwiftUI
import VitalSnapCore

@MainActor
@Observable
final class AppModel {
    var hasCompletedOnboarding: Bool
    let log: ReadingLogStore
    let health = HealthStoreService()

    init(previewData: Bool = false) {
        if previewData {
            hasCompletedOnboarding = true
            log = ReadingLogStore(previewReadings: LoggedReading.previewSamples)
            return
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        log = ReadingLogStore()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    private static let onboardingKey = "vitalsnap.hasCompletedOnboarding"
}
