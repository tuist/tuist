import Foundation
import Mockable

@Mockable
protocol BackgroundProcessRunning {
    func runInBackground(
        _ arguments: [String],
        environment: [String: String]
    ) throws
}

struct BackgroundProcessRunner: BackgroundProcessRunning {
    func runInBackground(
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
