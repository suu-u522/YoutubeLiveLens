import Foundation
import GoogleMobileAds
import UIKit

@MainActor
final class RewardedAdService: NSObject, ObservableObject {
    static let shared = RewardedAdService()

    // 本番では実際の広告ユニットIDに差し替える
    private let adUnitID = "ca-app-pub-2494717257898446/6096861446"

    @Published private(set) var isAdReady = false

    private var rewardedAd: GADRewardedAd?

    private override init() {
        super.init()
        Task { await load() }
    }

    func load() async {
        do {
            rewardedAd = try await GADRewardedAd.load(
                withAdUnitID: adUnitID,
                request: GADRequest()
            )
            rewardedAd?.fullScreenContentDelegate = self
            isAdReady = true
        } catch {
            isAdReady = false
        }
    }

    func show(from viewController: UIViewController, onRewarded: @escaping () -> Void) {
        guard let ad = rewardedAd else { return }
        ad.present(fromRootViewController: viewController) {
            onRewarded()
        }
    }
}

extension RewardedAdService: GADFullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            self.isAdReady = false
            await self.load()
        }
    }
}
