import Foundation
import TuistSupport

final class TuistService: NSObject {
    func run(_ arguments: [String]) throws {
        var arguments = arguments

        let commandName = "tuist-\(arguments[0])"
        arguments[0] = commandName

        try System.shared.runAndPrint(arguments)
    }
}
