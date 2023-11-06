import Foundation

/**
 It represents the interface of a tool that can collect warnings during the execution of a program and flush
 them when the program decides.
 */
public protocol WarningControlling {
    /// Appends a new warning to the list of warnings to be shown.
    /// - Parameter warning: The warning to be appended.
    func append(warning: String)

    /// Flushes the list of warnings printing them through the standard output.
    func flush()
}

public final class WarningController: WarningControlling {
    private let warningsQueue = DispatchQueue(label: "io.tuist.TuistSupport.WarningController")
    private var _warnings: [String] = []
    private var warnings: [String] {
        get {
            warningsQueue.sync { _warnings }
        }
        set {
            warningsQueue.sync { _warnings = newValue }
        }
    }

    public static var shared: WarningControlling = WarningController()

    private init() {}

    public func append(warning: String) {
        var warnings = warnings
        warnings.append(warning)
        self.warnings = warnings
    }

    public func flush() {
        let warnings = warnings
        self.warnings = []
        if warnings.count != 0 {
            logger
                .warning(
                    "\nThe following warnings need immediate attention:\n\(warnings.map { " · \($0)" }.joined(separator: "\n"))"
                )
        }
    }
}
