@testable import xcbuddykit

class MockUserInputRequester: UserInputRequesting {

    var boolUserInputStub: ((String) -> Bool)?
    var boolUserInputCount: UInt = 0
    var requiredUserInputStub: ((String, String) -> String)?
    var requiredUserInputCount: UInt = 0
    var optionalUserInputStub: ((String) -> String)?
    var optionalUserInputCount: UInt = 0
    
    func bool(message: String) -> Bool {
        boolUserInputCount += 1
        return boolUserInputStub?(message) ?? false
    }
    
    func required(message: String, errorMessage: String) -> String {
        requiredUserInputCount += 1
        return requiredUserInputStub?(message, errorMessage) ?? "required"
    }
    
    func optional(message: String) -> String? {
        optionalUserInputCount += 1
        return optionalUserInputStub?(message) ?? "optional"
    }
}
