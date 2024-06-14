import Foundation
import XcodeGraph

public protocol TargetMapping {
    func map(target: Target) throws -> (Target, [SideEffectDescriptor])
}
