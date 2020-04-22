import Foundation
import TuistSupport
import TSCBasic

protocol CertificateControlling {
    /// Returns certificate name
    func name(at path: AbsolutePath) throws -> String
}

final class CertificateController: CertificateControlling {
    func name(at path: AbsolutePath) throws -> String {
        let subjectName = try System.shared.capture("openssl", "x509", "-inform", "der", "-in", path.pathString, "-noout", "-subject")
        let nameRegex = try NSRegularExpression(pattern: "CN = ([^,]+),", options: [])
        guard let result = nameRegex.firstMatch(in: subjectName, options: [], range: NSRange(location: 0, length: subjectName.count)) else { fatalError() }
        return NSString(string: subjectName).substring(with: result.range(at: 1)).spm_chomp()
    }
}
