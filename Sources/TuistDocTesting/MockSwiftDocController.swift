import TuistDoc
@testable import TuistCore

final class MockSwiftDocController: SwiftDocControlling {
    func generate(format _: SwiftDocFormat,
                  moduleName _: String,
                  baseURL _: String,
                  outputDirectory _: String,
                  sourcesPath _: String) throws {}
}
