import Foundation

/// Protocol that represents an object that can ask the user
protocol InputRequering: AnyObject {

    /// Printer.
    var printer: Printing { get }
    
    /// Request to user a boolean question. User must to respond
    ///
    /// - Parameters:
    ///   - message: question text.
    func requestBoolUserInput(message: String) -> Bool
    
    /// Request to user a required question.
    ///
    /// - Parameters:
    ///   - message: question text.
    ///   - errorMessage: message to be showed when user doesn't respond.
    func requestRequiredUserInput(message: String, errorMessage: String) -> String
    
    /// Request to user a optional question. User can respond or not
    ///
    /// - Parameters:
    ///   - message: question text.
    func requestOptionalUserInput(message: String) -> String?
}

class InputRequerer: InputRequering {
    
    enum DefaultResponse {
        static let isRequired = "Please we need to know it. Try again."
        static let shouldBeBoolean = "Please enter Y (yes) or N (no). Try again"
    }
 
    /// Printer.
    let printer: Printing
    
    /// Initializes the input requerer with its attributess.
    ///
    /// - Parameters:
    ///   - printer: printer.
    init(printer: Printing = Printer()) {
        self.printer = printer
    }
    
    /// Request to user a boolean question.
    ///
    /// - Parameters:
    ///   - message: question text.
    func requestBoolUserInput(message: String) -> Bool {
        let answer = requestRequiredUserInput(message: "\(message) (Y/N)")
        
        switch answer.lowercased() {
        case "y":
            return true
        case "n":
            return false
        default:
            printer.print(warning: DefaultResponse.shouldBeBoolean)
            return requestBoolUserInput(message: message)
        }
    }
    
    /// Request to user a required question.
    ///
    /// - Parameters:
    ///   - message: question text.
    ///   - errorMessage: message to be showed when user doesn't respond.
    func requestRequiredUserInput(message: String, errorMessage: String = DefaultResponse.isRequired) -> String {
        printer.print(message)
        guard let response = readLine(), response.count > 0 else {
            printer.print(errorMessage: errorMessage)
            return requestRequiredUserInput(message: message)
        }
        return response
    }
    
    /// Request to user a optional question. User can respond or not
    ///
    /// - Parameters:
    ///   - message: question text.
    func requestOptionalUserInput(message: String) -> String? {
        printer.print(message)
        return readLine()
    }
}
