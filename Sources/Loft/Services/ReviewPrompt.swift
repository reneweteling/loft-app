import Foundation
import StoreKit

/// Asks for an App Store rating once, after enough uploads have gone well
/// that the person has an opinion. The GitHub build never asks: there is no
/// store page to rate. macOS decides whether the sheet actually appears.
enum ReviewPrompt {
    static let uploadsBeforeAsking = 10
    private static let countKey = "review.successfulUploads"
    private static let askedKey = "review.asked"

    @MainActor
    static func recordSuccessfulUpload() {
        guard Distribution.current == .appStore else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else { return }
        let count = defaults.integer(forKey: countKey) + 1
        defaults.set(count, forKey: countKey)
        guard count >= uploadsBeforeAsking else { return }
        defaults.set(true, forKey: askedKey)
        SKStoreReviewController.requestReview()
    }
}
