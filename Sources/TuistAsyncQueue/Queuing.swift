import Foundation
import Queuer

public protocol Queuing {
    func addOperation(_ operation: Operation)
    func resume()
    func waitUntilAllOperationsAreFinished()
}

extension Queuer: Queuing {}
