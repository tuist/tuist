import Foundation

protocol CommandRunning: AnyObject {
    func run() throws
}

class CommandRunner: CommandRunning {
    func run() throws {
    }
}
