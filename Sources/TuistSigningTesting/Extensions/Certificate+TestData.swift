import Foundation
import TSCBasic
@testable import TuistSigning

extension Certificate {
    static func test(
        publicKey: AbsolutePath = try! AbsolutePath(validating: "/"), // swiftlint:disable:this force_try
        privateKey: AbsolutePath = try! AbsolutePath(validating: "/"), // swiftlint:disable:this force_try
        fingerprint: String = "",
        developmentTeam: String = "",
        name: String = "",
        isRevoked: Bool = false
    ) -> Certificate {
        Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            fingerprint: fingerprint,
            developmentTeam: developmentTeam,
            name: name,
            isRevoked: isRevoked
        )
    }
}
