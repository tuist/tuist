import GoogleMobileAds
import UIKit

public class DynamicFrameworkA: NSObject {
    let googleAds = GADExtras()
    override public init() {
        super.init()
    }
}

extension DynamicFrameworkA: GADAdSizeDelegate {
    public func adView(_ bannerView: GADBannerView, willChangeAdSizeTo size: GADAdSize) {
        var frame = bannerView.frame
        frame.size.height = CGSizeFromGADAdSize(size).height
        print("new frame \(frame)")
    }
}
