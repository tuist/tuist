import Basic
import Foundation

/// Protocol that represents an object that can print messages.
public protocol Printing: AnyObject {
    /// Prints a message on the console.
    ///
    /// - Parameter text: message to be printed.
    func print(_ text: String)

    /// Prints a section.
    ///
    /// - Parameter section: section title.
    func print(section: String)

    /// Prints a warning message.
    ///
    /// - Parameter warning: message.
    func print(warning: String)

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    func print(error: Error)

    /// Prints a success message.
    ///
    /// - Parameter success: message.
    func print(success: String)

    /// Prints an error message.
    ///
    /// - Parameter errorMessage: error message to be printed.
    func print(errorMessage: String)
}

/// Default printer that conforms the printing protocol.
public class Printer: Printing {
    // swiftlint:disable force_cast
    let terminalController: TerminalController = TerminalController(stream: stdoutStream as! LocalFileOutputByteStream)!
    // swiftlint:enable force_cast

    public init() {}

    /// Prints a message on the console.
    ///
    /// - Parameter text: message to be printed.
    public func print(_ text: String) {
        let writer = InteractiveWriter.stdout
        writer.write(text)
        writer.write("\n")
    }

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    public func print(error: Error) {
        let writer = InteractiveWriter.stderr
        writer.write("❌ Error: ", inColor: .red, bold: true)
        writer.write(error.localizedDescription)
        writer.write("\n")
    }

    /// Prints a success message.
    ///
    /// - Parameter success: message.
    public func print(success: String) {
        let writer = InteractiveWriter.stdout
        writer.write("✅ Success: ", inColor: .green, bold: true)
        writer.write(success)
        writer.write("\n")
    }

    /// Prints a warning message.
    ///
    /// - Parameter warning: message.
    public func print(warning: String) {
        let writer = InteractiveWriter.stdout
        writer.write("⚠️ Warning: ", inColor: .yellow, bold: true)
        writer.write(warning)
        writer.write("\n")
    }

    /// Prints an error message.
    ///
    /// - Parameter errorMessage: error message.
    public func print(errorMessage: String) {
        let writer = InteractiveWriter.stderr
        writer.write("❌ Error: ", inColor: .red, bold: true)
        writer.write(errorMessage)
        writer.write("\n")
    }

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    public func print(section: String) {
        let writer = InteractiveWriter.stdout
        writer.write("\(section)", inColor: .cyan, bold: true)
        writer.write("\n")
        let separatorWith = (section.count < terminalController.width) ? section.count : terminalController.width
        writer.write(String(repeating: "=", count: separatorWith), inColor: .cyan, bold: true)
        writer.write("\n")
    }
}

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
        term = (stream as? LocalFileOutputByteStream).flatMap(TerminalController.init(stream:))
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
