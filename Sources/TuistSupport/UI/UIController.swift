import Foundation
import Noora

/// A controller for UI elements on the terminal.
public struct UIController: Noorable {
    // MARK: - Properties

    let noora: Noorable

    /// Flag to silent all output
    let isQuiet: Bool = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.quiet] != nil

    // MARK: - Initializer

    public init(noorable: Noorable) {
        self.noora = noorable
    }

    // MARK: - Methods

    /// Shows a text.
    ///
    /// - Parameters
    ///   - text: The text to show.
    public func message(_ text: TerminalText) {
        print("\(text.formatted(theme: .default, terminal: Terminal()))")
    }

    // MARK: - Noorable

    /// Shows a success alert.
    ///
    /// - Parameters:
    ///   - alert: The alert to show.
    public func success(_ alert: SuccessAlert) {
        if !isQuiet { noora.success(alert) }
    }

    /// Shows an error alert.
    ///
    /// - Parameters:
    ///   - alert: The alert to show.
    public func error(_ alert: ErrorAlert) {
        // ``isQuiet`` is not respected here, since errors should always be recorded
        noora.error(alert)
    }

    /// Shows warning alerts.
    ///
    /// - Parameters:
    ///   - alert: The alerts to show.
    public func warning(_ alerts: WarningAlert...) {
        if !isQuiet { noora.warning(alerts) }
    }

    /// Shows warning alerts.
    ///
    /// - Parameters:
    ///   - alert: The alerts to show.
    public func warning(_ alerts: [WarningAlert]) {
        if !isQuiet { noora.warning(alerts) }
    }

    /// Shows a progress step.
    ///
    /// - Parameters:
    ///   - message: The message that represents “what’s being done”
    ///   - successMessage: The message that the step gets updated to when the action completes.
    ///   - errorMessage: The message that the step gets updated to when the action errors.
    ///   - showSpinner: True to show a spinner.
    ///   - task: The asynchronous task to run. The caller can use the argument that the function takes to update the step
    /// message.
    public func progressStep(
        message: String,
        successMessage: String?,
        errorMessage: String?,
        showSpinner: Bool,
        task: @escaping ((String) -> Void) async throws -> Void
    ) async throws {
        if !isQuiet {
            try await noora.progressStep(
                message: message,
                successMessage: successMessage,
                errorMessage: errorMessage,
                showSpinner: showSpinner,
                task: task
            )
        }
    }

    /// A component to represent long-running operations showing the last lines of the sub-process, and collapsing it on
    /// completion.
    ///
    /// - Parameters:
    ///   - title: A representative title of the underlying operation.
    ///   - successMessage: A message that’s shown on success.
    ///   - errorMessage: A message that’s shown on completion
    ///   - visibleLines: The number of lines to show from the underlying task.
    ///   - task: The task to run.
    public func collapsibleStep(
        title: TerminalText,
        successMessage: TerminalText?,
        errorMessage: TerminalText?,
        visibleLines: UInt,
        task: @escaping (@escaping (TerminalText) -> Void) async throws -> Void
    ) async throws {
        if !isQuiet {
            try await noora.collapsibleStep(
                title: title,
                successMessage: successMessage,
                errorMessage: errorMessage,
                visibleLines: visibleLines,
                task: task
            )
        }
    }
}
