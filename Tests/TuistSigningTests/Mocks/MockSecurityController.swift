import TSCBasic
@testable import TuistSigning

final class MockSecurityController: SecurityControlling {
    var decodeFileStub: ((AbsolutePath) throws -> String)?
    var certificateExistsStub: ((AbsolutePath) throws -> Bool)?
    var importCertificateStub: ((AbsolutePath) throws -> Void)?

    func decodeFile(at path: AbsolutePath) throws -> String {
        try decodeFileStub?(path) ?? ""
    }

    func certificateExists(path: AbsolutePath) throws -> Bool {
        try certificateExistsStub?(path) ?? false
    }

    func importCertificate(at path: AbsolutePath) throws {
        try importCertificateStub?(path)
    }
}
