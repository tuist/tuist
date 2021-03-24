import Foundation
import TSCBasic
import TuistSupport

/// Struct used to pass around both flavors of Up.
public struct SetupActions {
    let actions: [Upping]
    let requires: [UpRequired]
}
