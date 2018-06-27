import Foundation

extension Process {
    /// Runs the file at the given path with the given arguments.
    /// It forwards the intputs/outputs from and to the standard input and output.
    /// This method blocks the thread until the execution of the process finishes, and then returns the termination status.
    ///
    /// - Parameters:
    ///   - path: path to the file to be executed.
    ///   - arguments: arguments to be passed.
    /// - Returns: the termination status.
    static func run(path: String, arguments: [String] = []) -> Int32 {
        let process = Process()
        process.launchPath = path
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handler in
            FileHandle.standardOutput.write(handler.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handler in
            FileHandle.standardError.write(handler.availableData)
        }
        FileHandle.standardInput.readabilityHandler = { handler in
            inputPipe.fileHandleForWriting.write(handler.availableData)
        }

        process.launch()
        process.waitUntilExit()

        return process.terminationStatus
    }
}
