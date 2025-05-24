import Combine
import Foundation
import TuistServerCore
import TuistSupport

@Observable
final class MenuBarViewModel: ObservableObject {
    private(set) var canCheckForUpdates: Bool = false

    func canCheckForUpdatesValueChanged(_ newValue: Bool) {
        canCheckForUpdates = newValue
    }
}
