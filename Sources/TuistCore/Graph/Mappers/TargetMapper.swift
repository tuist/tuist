import Foundation
import XcodeProjectGenerator

public protocol TargetMapping {
    func map(target: Target) throws -> (Target, [SideEffectDescriptor])
}
