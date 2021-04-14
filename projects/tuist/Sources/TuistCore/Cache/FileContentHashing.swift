import Foundation
import TSCBasic

public protocol FileContentHashing {
    func hash(path: AbsolutePath) throws -> String
}
