import Foundation

/// Interface to map targets.
public protocol ValueTargetMapping {
    /// Given a target, it maps it into another target and a list of side effects to be executed.
    /// - Parameter target: Target to be mapped.
    func map(target: Target) throws -> (Target, [SideEffectDescriptor])
}

/// A target mapper that is initialized with the mapping function.
class AnyValueTargetMapper: ValueTargetMapping {
    typealias ValueTargetMap = (Target) throws -> (Target, [SideEffectDescriptor])

    /// Mapping function.
    private let mapper: ValueTargetMap

    /// It initializes the mapper with a mapping function.
    /// - Parameter mapper: Mapping function.
    init(mapper: @escaping ValueTargetMap) {
        self.mapper = mapper
    }

    func map(target: Target) throws -> (Target, [SideEffectDescriptor]) {
        try mapper(target)
    }
}
