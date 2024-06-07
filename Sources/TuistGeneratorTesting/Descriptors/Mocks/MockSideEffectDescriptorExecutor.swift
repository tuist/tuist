import Foundation
import Path
import TuistCore
@testable import TuistGenerator

final class MockSideEffectDescriptorExecutor: SideEffectDescriptorExecuting {
    var executeStub: (([SideEffectDescriptor]) throws -> Void)?
    func execute(sideEffects: [SideEffectDescriptor]) throws {
        try executeStub?(sideEffects)
    }
}
