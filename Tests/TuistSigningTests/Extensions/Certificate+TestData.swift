import Foundation
import TSCBasic
@testable import TuistSigning

extension Certificate {
    static func test(publicKey: AbsolutePath = AbsolutePath("/"),
                     privateKey: AbsolutePath = AbsolutePath("/"),
                     developmentTeam: String = "",
                     name: String = "",
                     isRevoked: Bool = false) -> Certificate {
        Certificate(publicKey: publicKey,
                    privateKey: privateKey,
                    developmentTeam: developmentTeam,
                    name: name,
                    isRevoked: isRevoked)
    }
}
