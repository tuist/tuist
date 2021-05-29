import Foundation
import TSCBasic

@testable import TuistKit

final class MockTestServiceGeneratorFactory: TestServiceGeneratorFactorying {
    var generatorStub: ((AbsolutePath, AbsolutePath) -> Generating)?
    func generator(
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath
    ) -> Generating {
        generatorStub?(automationPath, testsCacheDirectory) ?? MockGenerator()
    }
}
