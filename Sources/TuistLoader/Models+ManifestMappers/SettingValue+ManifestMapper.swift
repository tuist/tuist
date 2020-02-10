import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.SettingValue {
    static func from(manifest: ProjectDescription.SettingValue) -> TuistCore.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}
