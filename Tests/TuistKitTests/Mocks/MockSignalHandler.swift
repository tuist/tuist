import Foundation
import TuistSupport

struct MockSignalHandler: SignalHandling {
    func trap(_: TuistSupport.SigActionHandler) {}
}
