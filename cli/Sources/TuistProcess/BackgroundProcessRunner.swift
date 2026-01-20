import AppKit
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
        let process = Foundation.Process()
        process.environment = environment
        process.launchPath = arguments.first
        process.arguments = Array(arguments.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.unbind(.isIndeterminate)
        try process.run()
    }
}
