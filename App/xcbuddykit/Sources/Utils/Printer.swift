import Basic
import Foundation

/// Protocol that represents an object that can print messages.
protocol Printing: AnyObject {
    /// Prints a message on the console.
    ///
    /// - Parameter text: message to be printed.
    func print(_ text: String)

    /// Prints a section.
    ///
    /// - Parameter section: section title.
    func print(section: String)

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    func print(error: Error)

    /// Prints an error message.
    ///
    /// - Parameter errorMessage: error message to be printed.
    func print(errorMessage: String)
}

/// Default printer that conforms the printing protocol.
class Printer: Printing {
    let terminalController: TerminalController = TerminalController(stream: stdoutStream as! LocalFileOutputByteStream)!

    /// Prints a message on the console.
    ///
    /// - Parameter text: message to be printed.
    func print(_ text: String) {
        let writer = InteractiveWriter.stdout
        writer.write(text)
        writer.write("\n")
    }

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    func print(error: Error) {
        let writer = InteractiveWriter.stderr
        writer.write("Error: ", inColor: .red, bold: true)
        writer.write(error.localizedDescription)
        writer.write("\n")
    }

    /// Prints an error message.
    ///
    /// - Parameter errorMessage: error message.
    func print(errorMessage: String) {
        let writer = InteractiveWriter.stderr
        writer.write("Error: ", inColor: .red, bold: true)
        writer.write(errorMessage)
        writer.write("\n")
    }

    /// Prints an error.
    ///
    /// - Parameter error: error to be printed.
    func print(section: String) {
        let writer = InteractiveWriter.stdout
        writer.write("\(section)", inColor: .green, bold: true)
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
