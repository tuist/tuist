import Foundation
import Utility

protocol Command {
    static var command: String { get }
    static var overview: String { get }
    init(parser: ArgumentParser)
    func run(with arguments: ArgumentParser.Result) throws
}
