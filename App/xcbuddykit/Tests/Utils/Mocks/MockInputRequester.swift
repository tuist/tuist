@testable import xcbuddykit

class MockInputRequester: InputRequering {
    
    enum Mode {
        case positive
        case negative
    }
    
    var mode: Mode = .positive
    let printer: Printing = MockPrinter()
    
    func requestBoolUserInput(message: String) -> Bool {
        return mode == .positive ? true : false
    }
    
    func requestRequiredUserInput(message: String, errorMessage: String) -> String {
        return "required"
    }
    
    func requestOptionalUserInput(message: String) -> String? {
        return mode == .positive ? "optional" : nil
    }
}
