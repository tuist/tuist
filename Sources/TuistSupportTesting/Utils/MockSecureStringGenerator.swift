import Foundation

@testable import TuistSupport

final class MockSecureStringGenerator: SecureStringGenerating {
    var generateStub: Result<String, Error>?

    func generate() throws -> String {
        if let generateStub = generateStub {
            return try generateStub.get()
        } else {
            throw TestError("Call to non-stubbed method generate")
        }
    }
}
