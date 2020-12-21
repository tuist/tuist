import Foundation
import TSCBasic

struct Certificate: Equatable {
    let publicKey: AbsolutePath
    let privateKey: AbsolutePath
    let fingerprint: String
    let developmentTeam: String
    let name: String
    let targetName: String
    let configurationName: String
    let isRevoked: Bool
}
