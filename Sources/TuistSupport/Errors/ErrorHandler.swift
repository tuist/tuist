import Foundation
import ServiceContextModule
import Noora

/// Objects that conform this protocol provide a way of handling fatal errors
/// that are thrown during the execution of an app.
public protocol ErrorHandling: AnyObject {
    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    func fatal(error: FatalError)
}

/// The default implementation of the ErrorHandling protocol
public final class ErrorHandler: ErrorHandling {
    // MARK: - Public

    public init() {}

    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    public func fatal(error: FatalError) {
        let isSilent = error.type == .abortSilent || error.type == .bugSilent
        if !error.description.isEmpty, !isSilent {
            ServiceContext.current?.ui?.error(
                .alert(
                "\(error.description)",
                nextSteps: ["Consider creating an issue using the following link: https://github.com/tuist/tuist/issues/new/choose"])
            )
        } else if error.type == .bugSilent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconveniences it might have caused.
            """
            ServiceContext.current?.ui?.error(.alert("\(message)"))
        }
    }
}
