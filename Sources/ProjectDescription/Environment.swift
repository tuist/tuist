import Foundation

@dynamicMemberLookup
public struct Environment {
    public enum Value {
        case boolean(Bool)
        case string(String)
    }

    public static subscript(dynamicMember member: String) -> Value? {
        let snakeCaseMember = "TUIST_\(member.camelCaseToSnakeCase().uppercased())"
        guard let value = ProcessInfo.processInfo.environment[snakeCaseMember] else { return nil }
        let trueValues = ["1", "true", "TRUE", "yes", "YES"]
        let falseValues = ["0", "false", "FALSE", "no", "NO"]
        if trueValues.contains(value) {
            return .boolean(true)
        } else if falseValues.contains(value) {
            return .boolean(false)
        } else {
            return .string(value)
        }
    }
}

private extension String {
    func camelCaseToSnakeCase() -> String {
        let acronymPattern = "([A-Z]+)([A-Z][a-z]|[0-9])"
        let normalPattern = "([a-z0-9])([A-Z])"
        return processCamalCaseRegex(pattern: acronymPattern)?
            .processCamalCaseRegex(pattern: normalPattern)?.lowercased() ?? lowercased()
    }

    func processCamalCaseRegex(pattern: String) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: count)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1_$2")
    }
}
