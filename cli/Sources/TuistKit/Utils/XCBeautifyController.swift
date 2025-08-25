import Foundation

/// Defines a protocol for controlling xcbeautify execution
protocol XCBeautifyControlling {
    /// Runs xcbeautify with the given arguments and build output
    ///
    /// - Parameters:
    ///   - arguments: The arguments to pass to xcbeautify
    ///   - buildOutput: The raw build output data to be piped into xcbeautify
    func run(arguments: [String], buildOutput: Data) async throws
}

final class XCBeautifyController: XCBeautifyControlling {
    func run(arguments: [String], buildOutput: Data) async throws {
        let xcbeautify = Process()
        xcbeautify.executableURL = URL(fileURLWithPath: "/usr/local/bin/xcbeautify")
        xcbeautify.arguments = arguments

        let inputPipe = Pipe()
        xcbeautify.standardInput = inputPipe

        try xcbeautify.run()

        try inputPipe.fileHandleForWriting.write(contentsOf: buildOutput)

        inputPipe.fileHandleForWriting.closeFile()

        xcbeautify.waitUntilExit()
    }
}
