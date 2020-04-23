import Foundation
import TSCBasic

struct Certificate: Equatable {
    let publicKey: AbsolutePath
    let privateKey: AbsolutePath
    let developmentTeam: String
    let name: String
    let isRevoked: Bool
}
