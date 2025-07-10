import Foundation
import SwiftUI

public struct NooraIcon: View {
    public enum Icon: String {
        case brandGoogle = "brand-google"
        case brandOkta = "brand-okta"
        case brandTuist = "brand-tuist"
        case chevronDown = "chevron-down"
        case deviceDesktop = "device-desktop"
        case deviceDesktopShare = "device-desktop-share"
        case deviceiPadHorizontal = "device-ipad-horizontal"
        case deviceiPadHorizontalShare = "device-ipad-horizontal-share"
        case deviceLaptop = "device-laptop"
        case deviceMobile = "device-mobile"
        case deviceMobileShare = "device-mobile-share"
        case deviceVisionPro = "device-vision-pro"
        case deviceVisionProShare = "device-vision-pro-share"
        case deviceWatch = "device-watch"
        case deviceWatchShare = "device-watch-share"
        case gitBranch = "git-branch"
        case history
        case refresh
        case settings
        case timelineEvent = "timeline-event"
        case user
    }

    private let icon: Icon

    public init(
        _ icon: Icon
    ) {
        self.icon = icon
    }

    public var body: some View {
        Image(icon.rawValue, bundle: TuistNooraResources.bundle)
            .resizable()
            .renderingMode(.template)
    }
}
