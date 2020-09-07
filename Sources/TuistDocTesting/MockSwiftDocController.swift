import TuistDoc

@testable import TuistCore

public final class MockSwiftDocController: SwiftDocControlling {
    public init() {}
    
    public var generateStub: ((SwiftDocFormat, String, String, String, String) throws -> Void)?
    public func generate(format _: SwiftDocFormat,
                         moduleName _: String,
                         baseURL _: String,
                         outputDirectory _: String,
                         sourcesPath _: String) throws {}
}
