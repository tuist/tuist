import TSCBasic
@testable import TuistSigningTesting
@testable import TuistSigning

final class MockCertificateParser: CertificateParsing {
    var parseStub: ((AbsolutePath, AbsolutePath) throws -> Certificate)?
    func parse(publicKey: AbsolutePath, privateKey: AbsolutePath) throws -> Certificate {
        try parseStub?(publicKey, privateKey) ?? Certificate.test()
    }
}
