import Foundation

public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation {
    public let target: TargetReference
    public let isSkipped: Bool
    public let isParallelizable: Bool
    public let isRandomExecutionOrdering: Bool

    public init(
        target: TargetReference,
        skipped: Bool = false,
        parallelizable: Bool = false,
        randomExecutionOrdering: Bool = false
    ) {
        self.target = target
        isSkipped = skipped
        isParallelizable = parallelizable
        isRandomExecutionOrdering = randomExecutionOrdering
    }

    public init(stringLiteral value: String) {
        self.init(target: .init(projectPath: nil, target: value))
    }
}
