import Foundation
import TSCBasic
import TuistSupport

enum CertificateParserError: FatalError, Equatable {
    case nameParsingFailed(AbsolutePath, String)
    case developmentTeamParsingFailed(AbsolutePath, String)
    case fileParsingFailed(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .nameParsingFailed, .developmentTeamParsingFailed, .fileParsingFailed:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .nameParsingFailed(path, input):
            return "We couldn't parse the name while parsing the following output from the file \(path.pathString): \(input)"
        case let .developmentTeamParsingFailed(path, input):
            return "We couldn't parse the development team while parsing the following output from the file \(path.pathString): \(input)"
        case let .fileParsingFailed(path):
            return "We couldn't parse the file \(path.pathString)"
        }
    }
}

/// Used to parse and extract info from a certificate
protocol CertificateParsing {
    /// Parse public-private key pair
    /// - Returns: Parse `Certificate`
    func parse(publicKey: AbsolutePath, privateKey: AbsolutePath) throws -> Certificate

    /// Retrieve fingerprint of a public key
    func parseFingerPrint(developerCertificate: Data) throws -> String
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
        let subject = try subject(at: publicKey)
        let fingerprint = try fingerprint(at: publicKey)
        let isRevoked = subject.contains("REVOKED")

        let nameRegex = try NSRegularExpression(
            pattern: SubjectAttribute.commonName.rawValue + " *= *([^/,]+)",
            options: []
        )
        guard let nameResult = nameRegex.firstMatch(in: subject, options: [], range: NSRange(location: 0, length: subject.count))
        else { throw CertificateParserError.nameParsingFailed(publicKey, subject) }
        let name = NSString(string: subject).substring(with: nameResult.range(at: 1)).spm_chomp()

        let developmentTeamRegex = try NSRegularExpression(
            pattern: SubjectAttribute.organizationalUnit.rawValue + " *= *([^/,]+)",
            options: []
        )
        guard let developmentTeamResult = developmentTeamRegex.firstMatch(
            in: subject,
            options: [],
            range: NSRange(location: 0, length: subject.count)
        )
        else { throw CertificateParserError.developmentTeamParsingFailed(publicKey, subject) }
        let developmentTeam = NSString(string: subject).substring(with: developmentTeamResult.range(at: 1)).spm_chomp()

        return Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            fingerprint: fingerprint,
            developmentTeam: developmentTeam,
            name: name.sanitizeEncoding(),
            isRevoked: isRevoked
        )
    }

    func parseFingerPrint(developerCertificate: Data) throws -> String {
        let temporaryFile = try FileHandler.shared.temporaryDirectory().appending(component: "developerCertificate.cer")
        try developerCertificate.write(to: temporaryFile.asURL)

        return try fingerprint(at: temporaryFile)
    }

    // MARK: - Helpers

    private func subject(at path: AbsolutePath) throws -> String {
        do {
            return try System.shared.capture(["openssl", "x509", "-inform", "der", "-in", path.pathString, "-noout", "-subject"])
        } catch let TuistSupport.SystemError.terminated(_, _, standardError) {
            if let string = String(data: standardError, encoding: .utf8) {
                logger.warning("Parsing subject of \(path) failed with: \(string)")
            }
            throw CertificateParserError.fileParsingFailed(path)
        } catch {
            throw CertificateParserError.fileParsingFailed(path)
        }
    }

    private func fingerprint(at path: AbsolutePath) throws -> String {
        do {
            return try System.shared
                .capture(["openssl", "x509", "-inform", "der", "-in", path.pathString, "-noout", "-fingerprint"]).spm_chomp()
        } catch let TuistSupport.SystemError.terminated(_, _, standardError) {
            if let string = String(data: standardError, encoding: .utf8) {
                logger.warning("Parsing fingerprint of \(path) failed with: \(string)")
            }
            throw CertificateParserError.fileParsingFailed(path)
        } catch {
            throw CertificateParserError.fileParsingFailed(path)
        }
    }
}

extension String {
    func sanitizeEncoding() -> String {
        // Had some real life certificates where encoding in the name was broken - e.g. \\xC3\\xA4 instead of ä
        guard let regex = try? NSRegularExpression(pattern: "(\\\\x([A-Za-z0-9]{2}))(\\\\x([A-Za-z0-9]{2}))", options: [])
        else { return self }
        let matches = regex.matches(in: self, options: [], range: NSRange(startIndex..., in: self)).reversed()

        var modifiableString = self
        matches.forEach { result in
            guard let firstRange = Range(result.range(at: 2), in: modifiableString),
                  let secondRange = Range(result.range(at: 4), in: modifiableString),
                  let firstInt = UInt8(modifiableString[firstRange], radix: 16),
                  let secondInt = UInt8(modifiableString[secondRange], radix: 16)
            else {
                return
            }
            let resultRange = Range(result.range, in: modifiableString)!
            modifiableString.replaceSubrange(
                resultRange,
                with: String(decoding: [firstInt, secondInt] as [UTF8.CodeUnit], as: UTF8.self)
            )
        }

        return modifiableString
    }
}
