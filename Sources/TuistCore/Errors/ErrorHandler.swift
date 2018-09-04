import Foundation

public protocol ErrorHandling: AnyObject {
    func fatal(error: FatalError)
}

public final class ErrorHandler: ErrorHandling {
    // MARK: - Attributes

    let printer: Printing
    var exiter: (Int32) -> Void

    // MARK: - Init

    public convenience init(printer: Printing = Printer()) {
        self.init(printer: printer, exiter: { exit($0) })
    }

    init(printer: Printing,
         exiter: @escaping (Int32) -> Void) {
        self.printer = printer
        self.exiter = exiter
    }

    // MARK: - Public

    public func fatal(error: FatalError) {
        let isSilent = error.type == .abortSilent || error.type == .bugSilent
        if !error.description.isEmpty && !isSilent {
            printer.print(errorMessage: error.description)
        } else if isSilent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconveniences it might have caused.
            """
            printer.print(errorMessage: message)
        }
        exiter(1)
    }
}
