import Foundation

public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation {
    public var target: TargetReference
    public var isSkipped: Bool
    public var isParallelizable: Bool
    public var isRandomExecutionOrdering: Bool

    init(
        target: TargetReference,
        isSkipped: Bool,
        isParallelizable: Bool,
        isRandomExecutionOrdering: Bool
    ) {
        self.target = target
        self.isSkipped = isSkipped
        self.isParallelizable = isParallelizable
        self.isRandomExecutionOrdering = isRandomExecutionOrdering
    }
    
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        isParallelizable: Bool = false,
        isRandomExecutionOrdering: Bool = false
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            isParallelizable: isParallelizable,
            isRandomExecutionOrdering: isRandomExecutionOrdering
        )
    }

    public init(stringLiteral value: String) {
        self.init(
            target: TargetReference(projectPath: nil, target: value),
            isSkipped: false,
            isParallelizable: false,
            isRandomExecutionOrdering: false
        )
    }
}
