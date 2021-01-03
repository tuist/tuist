import Foundation
import TSCBasic
@testable import TuistSigning
@testable import TuistSigningTesting

final class MockCertificateParser: CertificateParsing {
    var parseStub: ((AbsolutePath, AbsolutePath) throws -> Certificate)?
    func parse(publicKey: AbsolutePath, privateKey: AbsolutePath) throws -> Certificate {
        try parseStub?(publicKey, privateKey) ?? Certificate.test()
    }

    var parseFingerPrintStub: ((Data) throws -> String)?
    func parseFingerPrint(developerCertificate: Data) throws -> String {
        try parseFingerPrintStub?(developerCertificate) ?? ""
    }
}
