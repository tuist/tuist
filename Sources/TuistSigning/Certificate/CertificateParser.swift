import Foundation
import TSCBasic
import TuistSupport

enum CertificateParserError: FatalError, Equatable {
    case nameParsingFailed(AbsolutePath, String)
    case developmentTeamParsingFailed(AbsolutePath, String)
    case invalidFormat(String)

    var type: ErrorType {
        switch self {
        case .nameParsingFailed, .developmentTeamParsingFailed, .invalidFormat:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .invalidFormat(certificate):
            return "Certificate \(certificate) is in invalid format. Please name your certificates in the following way: Target.Configuration.p12"
        case let .nameParsingFailed(path, input):
            return "We couldn't parse the name while parsing the following output from the file \(path.pathString): \(input)"
        case let .developmentTeamParsingFailed(path, input):
            return "We couldn't parse the development team while parsing the following output from the file \(path.pathString): \(input)"
        }
    }
}

/// Used to parse and extract info from a certificate
protocol CertificateParsing {
    /// Parse public-private key pair
    /// - Returns: Parse `Certificate`
    func parse(publicKey: AbsolutePath, privateKey: AbsolutePath) throws -> Certificate
}

/// Subject attributes that are returnen with `openssl x509 -subject`
private enum SubjectAttribute: String {
    case commonName = "CN"
    case country = "C"
    case description
    case emailAddress
    case locality = "L"
    case organization = "O"
    case organizationalUnit = "OU"
    case state = "ST"
    case uid = "UID"
}

final class CertificateParser: CertificateParsing {
    func parse(publicKey: AbsolutePath, privateKey: AbsolutePath) throws -> Certificate {
        let publicKeyComponents = publicKey.basenameWithoutExt.components(separatedBy: ".")
        guard publicKeyComponents.count == 2 else { throw CertificateParserError.invalidFormat(publicKey.pathString) }
        let targetName = publicKeyComponents[0]
        let configurationName = publicKeyComponents[1]

        let subject = try self.subject(at: publicKey)
        let isRevoked = subject.contains("REVOKED")

        let nameRegex = try NSRegularExpression(
            pattern: SubjectAttribute.commonName.rawValue + " *= *([^/,]+)",
            options: []
        )
        guard
            let result = nameRegex.firstMatch(in: subject, options: [], range: NSRange(location: 0, length: subject.count))
        else { throw CertificateParserError.nameParsingFailed(publicKey, subject) }
        let name = NSString(string: subject).substring(with: result.range(at: 1)).spm_chomp()

        let developmentTeamRegex = try NSRegularExpression(
            pattern: SubjectAttribute.organizationalUnit.rawValue + " *= *([^/,]+)",
            options: []
        )
        guard
            let developmentTeamResult = developmentTeamRegex.firstMatch(in: subject, options: [], range: NSRange(location: 0, length: subject.count))
        else { throw CertificateParserError.developmentTeamParsingFailed(publicKey, subject) }
        let developmentTeam = NSString(string: subject).substring(with: developmentTeamResult.range(at: 1)).spm_chomp()

        return Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            developmentTeam: developmentTeam,
            name: name.sanitizeEncoding(),
            targetName: targetName,
            configurationName: configurationName,
            isRevoked: isRevoked
        )
    }

    // MARK: - Helpers

    private func subject(at path: AbsolutePath) throws -> String {
        try System.shared.capture("openssl", "x509", "-inform", "der", "-in", path.pathString, "-noout", "-subject")
    }
}

private extension String {
    func sanitizeEncoding() -> String {
        // we had certificates where encoding in the name was broken - e.g. \\xC3\\xA4 instead of ä
        guard let regex = try? NSRegularExpression(pattern: "(\\\\x([A-Z0-9]{2}))(\\\\x([A-Z0-9]{2}))", options: []) else { return self }
        let matches = regex.matches(in: self, options: [], range: NSRange(startIndex..., in: self)).reversed()

        var modifiableString = self
        matches.forEach { result in
            guard let firstRange = Range(result.range(at: 2), in: modifiableString), let secondRange = Range(result.range(at: 4), in: modifiableString) else { return }
            guard let firstInt = UInt8(modifiableString[firstRange], radix: 16), let secondInt = UInt8(modifiableString[secondRange], radix: 16) else { return }
            modifiableString.replaceSubrange(Range(result.range, in: modifiableString)!, with: String(decoding: [firstInt, secondInt] as [UTF8.CodeUnit], as: UTF8.self))
        }

        return modifiableString
    }
}
