import Foundation
import TSCBasic
import TuistDoc
import TuistSupportTesting
@testable import TuistCore

public final class MockSwiftDocController: SwiftDocControlling {
    public init() {}

    public var generateStub: ((SwiftDocFormat, String, String, String, [AbsolutePath]) throws -> Void)?
    public func generate(format: SwiftDocFormat,
                         moduleName: String,
                         baseURL: String,
                         outputDirectory: String,
                         sourcesPaths: [AbsolutePath]) throws
    {
        guard let generateStub = generateStub else { throw NSError.test() }
        try generateStub(format, moduleName, baseURL, outputDirectory, sourcesPaths)
    }
}
