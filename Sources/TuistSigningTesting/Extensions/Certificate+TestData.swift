import Foundation
import TSCBasic
@testable import TuistSigning

extension Certificate {
    static func test(publicKey: AbsolutePath = AbsolutePath("/"),
                     privateKey: AbsolutePath = AbsolutePath("/"),
                     fingerprint: String = "",
                     developmentTeam: String = "",
                     name: String = "",
                     targetName: String = "",
                     configurationName: String = "",
                     isRevoked: Bool = false) -> Certificate
    {
        Certificate(publicKey: publicKey,
                    privateKey: privateKey,
                    fingerprint: fingerprint,
                    developmentTeam: developmentTeam,
                    name: name,
                    targetName: targetName,
                    configurationName: configurationName,
                    isRevoked: isRevoked)
    }
}
