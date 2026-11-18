import Foundation

enum TestCaseIdentifier {
    case id(String)
    case name(moduleName: String, suiteName: String?, testName: String)

    /// The module is the first part and the test the last; everything between is the suite, since a
    /// nested Swift Testing suite is recorded as `Outer/Inner`. A part can percent-encode a `/` or `%`
    /// it holds (`%2F`, `%25`), as tuist_ex does for Mix describe names such as `create_order/2`.
    init(_ identifier: String) throws {
        if identifier.contains("/") {
            let parts = identifier.split(separator: "/", omittingEmptySubsequences: true).map { Self.decode(String($0)) }
            switch parts.count {
            case 2:
                self = .name(moduleName: parts[0], suiteName: nil, testName: parts[1])
            case 3...:
                self = .name(
                    moduleName: parts[0],
                    suiteName: parts[1 ..< parts.count - 1].joined(separator: "/"),
                    testName: parts[parts.count - 1]
                )
            default:
                throw TestCaseIdentifierError.invalidIdentifier(identifier)
            }
        } else {
            self = .id(identifier)
        }
    }

    private static func decode(_ part: String) -> String {
        var decoded = ""
        var index = part.startIndex
        while index < part.endIndex {
            let rest = part[index...]
            if rest.hasPrefix("%2F") || rest.hasPrefix("%2f") || rest.hasPrefix("%25") {
                decoded.append(rest.hasPrefix("%25") ? "%" : "/")
                index = part.index(index, offsetBy: 3)
            } else {
                decoded.append(part[index])
                index = part.index(after: index)
            }
        }
        return decoded
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
