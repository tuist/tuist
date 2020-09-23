import Foundation

public protocol TargetMapping {
    func map(target: Target) throws -> (Target, [SideEffectDescriptor])
}
