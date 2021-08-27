import Foundation
import TSCBasic

@testable import TuistKit

final class MockTestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    var generatorStub: ((AbsolutePath, AbsolutePath, Bool, Bool) -> Generating)?
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool,
        skipCache: Bool
    ) -> Generating {
        generatorStub?(automationPath, testsCacheDirectory, skipUITests, skipCache) ?? MockGenerator()
    }
}
