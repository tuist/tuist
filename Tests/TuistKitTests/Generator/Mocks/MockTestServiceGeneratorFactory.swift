import Foundation
import TSCBasic

@testable import TuistKit

final class MockTestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    var generatorStub: ((AbsolutePath, AbsolutePath, Bool) -> Generating)?
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating {
        generatorStub?(automationPath, testsCacheDirectory, skipUITests) ?? MockGenerator()
    }
}
