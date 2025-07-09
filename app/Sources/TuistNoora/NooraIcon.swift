import Foundation
import SwiftUI

public struct NooraIcon: View {
    public enum Icon: String {
        case brandGoogle = "brand-google"
        case brandOkta = "brand-okta"
        case brandTuist = "brand-tuist"
        case chevronDown = "chevron-down"
        case deviceMobile = "device-mobile"
        case gitBranch = "git-branch"
        case history
        case timelineEvent = "timeline-event"
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
