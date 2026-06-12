import AVKit
import CoreMedia
import UIKit

@MainActor
final class DisplayCriteriaManager {

    static let shared = DisplayCriteriaManager()
    private init() {}

    func applyNative(formatDescription: CMVideoFormatDescription, refreshRate: Float) {
        guard let window = activeWindow() else { return }
        let manager = window.avDisplayManager
        guard manager.isDisplayCriteriaMatchingEnabled else { return }
        if #available(tvOS 17.0, *) {
            manager.preferredDisplayCriteria = AVDisplayCriteria(
                refreshRate: refreshRate,
                formatDescription: formatDescription
            )
        } else {
            manager.preferredDisplayCriteria = nil
        }
    }

    func reset() {
        guard let window = activeWindow() else { return }
        window.avDisplayManager.preferredDisplayCriteria = nil
    }

    private func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }
}
