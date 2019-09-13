import Basic
import Foundation

public protocol Printing: AnyObject {
    func print(_ text: String)
    func print(section: String)
    func print(subsection: String)
    func print(warning: String)
    func print(error: Error)
    func print(success: String)
    func print(errorMessage: String)
    func print(deprecation: String)
}

public class Printer: Printing {
    /// Shared instance
    public static var shared: Printing = Printer()

    // MARK: - Init

    init() {}

    // MARK: - Public

    public func print(_ text: String) {
        printStandardOutputLine(text)
    }

    public func print(error: Error) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardErrorLine(error.localizedDescription.red().bold())
        } else {
            printStandardErrorLine("Error: \(error.localizedDescription)")
        }
    }

    public func print(success: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(success.green().bold())
        } else {
            printStandardOutputLine("Success: \(success)")
        }
    }

    /// Prints a deprecation message (yellow color)
    ///
    /// - Parameter deprecation: Deprecation message.
    public func print(deprecation: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(deprecation.yellow().bold())
        } else {
            printStandardOutputLine("Deprecated: \(deprecation)")
        }
    }

    public func print(warning: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(warning.yellow().bold())
        } else {
            printStandardOutputLine("Warning: \(warning)")
        }
    }

    public func print(errorMessage: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardErrorLine(errorMessage.red().bold())
        } else {
            printStandardErrorLine("Error: \(errorMessage)")
        }
    }

    public func print(section: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(section.cyan().bold())
        } else {
            printStandardOutputLine(section)
        }
    }

    public func print(subsection: String) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(subsection.cyan())
        } else {
            printStandardOutputLine(subsection)
        }
    }

    // MARK: - Fileprivate

    fileprivate func printStandardOutputLine(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }

    fileprivate func printStandardErrorLine(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        FileHandle.standardError.write("\n".data(using: .utf8)!)
    }
}
