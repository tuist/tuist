import Foundation
import Mockable

@Mockable
public protocol BackgroundProcessRunning {
    func runInBackground(
        _ arguments: [String],
        environment: [String: String]
    ) throws
}

public struct BackgroundProcessRunner: BackgroundProcessRunning {
    public init() {}

    public func runInBackground(
        _ arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process()
        process.environment = environment
        process.launchPath = arguments.first
        process.arguments = Array(arguments.dropFirst())
        process.unbind(.isIndeterminate)
        try process.run()
    }
}
