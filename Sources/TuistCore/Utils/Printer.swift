import Basic
import Foundation

public enum PrinterOutput {
    case standardOputput
    case standardError
}

public protocol Printing: AnyObject {
    func print(_ text: String)
    func print(_ text: String, output: PrinterOutput)
    func print(_ text: String, color: TerminalController.Color)
    func print(section: String)
    func print(subsection: String)
    func print(warning: String)
    func print(error: Error)
    func print(success: String)
    func print(errorMessage: String)

    /// Prints a deprecation message (yellow color)
    ///
    /// - Parameter deprecation: Deprecation message.
    func print(deprecation: String)
}

public class Printer: Printing {
    // MARK: - Init

    public init() {}

    // MARK: - Public

    public func print(_ text: String) {
        print(text, output: .standardOputput)
    }

    public func print(_ text: String, output: PrinterOutput) {
        let writer: InteractiveWriter!
        if output == .standardOputput {
            writer = .stdout
        } else {
            writer = .stderr
        }

        writer.write(text)
        writer.write("\n")
    }

    public func print(_ text: String, color: TerminalController.Color) {
        let writer = InteractiveWriter.stdout
        writer.write(text, inColor: color, bold: false)
        writer.write("\n")
    }

    public func print(error: Error) {
        let writer = InteractiveWriter.stderr
        writer.write("Error: ", inColor: .red, bold: true)
        writer.write(error.localizedDescription)
        writer.write("\n")
    }

    public func print(success: String) {
        let writer = InteractiveWriter.stdout
        writer.write("Success: ", inColor: .green, bold: true)
        writer.write(success)
        writer.write("\n")
    }

    /// Prints a deprecation message (yellow color)
    ///
    /// - Parameter deprecation: Deprecation message.
    public func print(deprecation: String) {
        let writer = InteractiveWriter.stdout
        writer.write("Deprecated: ", inColor: .yellow, bold: true)
        writer.write(deprecation, inColor: .yellow, bold: true)
        writer.write("\n")
    }

    public func print(warning: String) {
        let writer = InteractiveWriter.stdout
        writer.write("Warning: ", inColor: .yellow, bold: true)
        writer.write(warning, inColor: .yellow, bold: true)
        writer.write("\n")
    }

    public func print(errorMessage: String) {
        let writer = InteractiveWriter.stderr
        writer.write("Error: ", inColor: .red, bold: true)
        writer.write(errorMessage, inColor: .red, bold: true)
        writer.write("\n")
    }

    public func print(section: String) {
        let writer = InteractiveWriter.stdout
        writer.write("\(section)", inColor: .cyan, bold: true)
        writer.write("\n")
    }

    public func print(subsection: String) {
        let writer = InteractiveWriter.stdout
        writer.write("\(subsection)", inColor: .cyan, bold: false)
        writer.write("\n")
    }
}

/// This class is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
final class InteractiveWriter {
    /// The standard error writer.
    static let stderr = InteractiveWriter(stream: stderrStream)

    /// The standard output writer.
    static let stdout = InteractiveWriter(stream: stdoutStream)

    /// The terminal controller, if present.
    let term: TerminalController?

    /// The output byte stream reference.
    let stream: OutputByteStream

    /// Create an instance with the given stream.
    init(stream: OutputByteStream) {
        term = TerminalController(stream: stream)
        self.stream = stream
    }

    /// Write the string to the contained terminal or stream.
    func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }
}
