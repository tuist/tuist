import Basic
import Foundation
import TuistGenerator
@testable import TuistKit

final class MockPlaygroundGenerator: PlaygroundGenerating {
    var generateCallCount: UInt = 0
    var generateStub: Error?
    var generateArgs: [(AbsolutePath, String, Platform, String)] = []

    func generate(path: AbsolutePath, name: String, platform: Platform, content: String) throws {
        generateCallCount += 1
        generateArgs.append((path, name, platform, content))
        if let generateStub = generateStub {
            throw generateStub
        }
    }
}
