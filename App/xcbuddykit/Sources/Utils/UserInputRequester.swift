import Foundation

/// Protocol that represents an object that can ask the user
protocol UserInputRequesting: AnyObject {
    
    /// Request to user a boolean question. User must to respond
    ///
    /// - Parameters:
    ///   - message: question text.
    func bool(message: String) -> Bool
    
    /// Request to user a required question.
    ///
    /// - Parameters:
    ///   - message: question text.
    ///   - errorMessage: message to be showed when user doesn't respond.
    func required(message: String, errorMessage: String) -> String
    
    /// Request to user a optional question. User can respond or not
    ///
    /// - Parameters:
    ///   - message: question text.
    func optional(message: String) -> String?
}

class UserInputRequester: UserInputRequesting {
    
    enum DefaultResponse {
        static let isRequired = "Please we need to know it. Try again."
        static let shouldBeBoolean = "Please enter Y (yes) or N (no). Try again"
    }
 
    /// Printer.
    let printer: Printing
    
    /// Read block.
    var readBlock: () -> String?
    
    /// Initializes the input requerer with its attributess.
    ///
    /// - Parameters:
    ///   - printer: printer.
    init(printer: Printing = Printer(), readBlock: @escaping () -> String? = { return readLine() }) {
        self.printer = printer
        self.readBlock = readBlock
    }
    
    /// Request to user a boolean question.
    ///
    /// - Parameters:
    ///   - message: question text.
    func bool(message: String) -> Bool {
        let answer = required(message: "\(message) (Y/N)")
        
        switch answer.lowercased() {
        case "y":
            return true
        case "n":
            return false
        default:
            printer.print(warning: DefaultResponse.shouldBeBoolean)
            return bool(message: message)
        }
    }
    
    /// Request to user a required question.
    ///
    /// - Parameters:
    ///   - message: question text.
    ///   - errorMessage: message to be showed when user doesn't respond.
    func required(message: String, errorMessage: String = DefaultResponse.isRequired) -> String {
        printer.print(message)
        guard let response = readBlock(), response.count > 0 else {
            printer.print(errorMessage: errorMessage)
            return required(message: message)
        }
        return response
    }
    
    /// Request to user a optional question. User can respond or not
    ///
    /// - Parameters:
    ///   - message: question text.
    func optional(message: String) -> String? {
        printer.print(message)
        return readBlock()
    }
}
