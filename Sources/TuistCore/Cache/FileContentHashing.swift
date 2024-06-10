import Foundation
import Path

public protocol FileContentHashing {
    func hash(path: AbsolutePath) throws -> String
}
