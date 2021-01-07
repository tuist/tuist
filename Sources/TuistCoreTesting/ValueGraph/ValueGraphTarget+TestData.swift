import Foundation
import TSCBasic

@testable import TuistCore

public extension ValueGraphTarget {
    static func test(path: AbsolutePath = .root,
                     target: Target = .test(),
                     project: Project = .test()) -> ValueGraphTarget {
        ValueGraphTarget(path: path,
                         target: target,
                         project: project)
    }
}
