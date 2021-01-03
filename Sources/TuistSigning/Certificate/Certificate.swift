import Foundation
import TSCBasic

struct Certificate: Equatable {
    let publicKey: AbsolutePath
    let privateKey: AbsolutePath
    /// Content of the fingerprint property of the public key
    let fingerprint: String
    let developmentTeam: String
    let name: String
    let isRevoked: Bool
}
