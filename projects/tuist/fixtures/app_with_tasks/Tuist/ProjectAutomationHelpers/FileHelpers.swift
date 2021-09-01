import Foundation
import ProjectAutomation

extension String {
    public func write(
        to pathString: String
    ) throws {
        try write(
           to: URL(fileURLWithPath: pathString),
            atomically: true,
            encoding: .utf8
        )
    }
}