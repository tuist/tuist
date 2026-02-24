import Foundation

enum TestCaseIdentifier {
    case id(String)
    case name(moduleName: String, suiteName: String?, testName: String)

    init(_ identifier: String) throws {
        if identifier.contains("/") {
            let parts = identifier.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            switch parts.count {
            case 3:
                self = .name(moduleName: parts[0], suiteName: parts[1], testName: parts[2])
            case 2:
                self = .name(moduleName: parts[0], suiteName: nil, testName: parts[1])
            default:
                throw TestCaseIdentifierError.invalidIdentifier(identifier)
            }
        } else {
            self = .id(identifier)
        }
    }
}

enum TestCaseIdentifierError: Equatable, LocalizedError {
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(identifier):
            return "Invalid test case identifier '\(identifier)'. Expected a UUID or the format Module/Suite/TestCase (or Module/TestCase)."
        }
    }
}
