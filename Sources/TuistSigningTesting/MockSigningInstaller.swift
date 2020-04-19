import TSCBasic
@testable import TuistSigning

public final class MockSigningInstaller: SigningInstalling {
    public init() {}

    public var installSigningStub: ((AbsolutePath) throws -> Void)?

    public func installSigning(at path: AbsolutePath) throws {
        try installSigningStub?(path)
    }
}
