import Foundation
import TuistCore

extension CacheOutputType {
    init(xcframeworksType: CacheXCFrameworkType?) {
        switch xcframeworksType {
        case .device:
            self = .deviceXCFramework
        case .simulator:
            self = .simulatorXCFramework
        case nil:
            self = .xcframework
        }
    }
}
