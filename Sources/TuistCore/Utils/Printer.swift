import Basic
import Foundation

public protocol Printing: AnyObject {
    func print(_ text: String)
    func print(section: String)
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
        writer.write(warning)
        writer.write("\n")
    }

    public func print(errorMessage: String) {
        let writer = InteractiveWriter.stderr
        writer.write("❌ Error: ", inColor: .red, bold: true)
        writer.write(errorMessage)
        writer.write("\n")
    }

    public func print(section: String) {
        let writer = InteractiveWriter.stdout
        writer.write("\(section)", inColor: .cyan, bold: true)
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
