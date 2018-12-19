import Basic
import Foundation

public protocol Printing: AnyObject {
    func print(_ text: String)
    func print(_ text: String, color: TerminalController.Color)
    func print(section: String)
    func print(subsection: String)
    func print(warning: String)
    func print(error: Error)
    func print(success: String)
    func print(errorMessage: String)
}

public class Printer: Printing {
    // MARK: - Init

    public init() {}

    // MARK: - Public

    public func print(_ text: String) {
        let writer = InteractiveWriter.stdout
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
        writer.write("❌ Error: ", inColor: .red, bold: true)
        writer.write(error.localizedDescription)
        writer.write("\n")
    }

    public func print(success: String) {
        let writer = InteractiveWriter.stdout
        writer.write("✅ Success: ", inColor: .green, bold: true)
        writer.write(success)
        writer.write("\n")
    }

    public func print(warning: String) {
        let writer = InteractiveWriter.stdout
        writer.write("⚠️  Warning: ", inColor: .yellow, bold: true)
        writer.write(warning, inColor: .yellow, bold: false)
        writer.write("\n")
    }

    public func print(errorMessage: String) {
        let writer = InteractiveWriter.stderr
        writer.write("❌ Error: ", inColor: .red, bold: true)
        writer.write(errorMessage, inColor: .red, bold: false)
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

final class InteractiveWriter {
    // MARK: - Attributes

    static let stderr = InteractiveWriter(stream: stderrStream)
    static let stdout = InteractiveWriter(stream: stdoutStream)
    let term: TerminalController?
    let stream: OutputByteStream

    // MARK: - Init

    init(stream: OutputByteStream) {
        term = (stream as? LocalFileOutputByteStream).flatMap(TerminalController.init(stream:))
        self.stream = stream
    }

    // MARK: - Internal

    func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }
}
