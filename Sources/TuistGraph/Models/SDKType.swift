import Foundation

public enum SDKType: String, CaseIterable, Equatable {
    case framework
    case library = "tbd"

    public static var supportedTypesDescription: String {
        let supportedTypes = allCases
            .map { ".\($0.rawValue)" }
            .joined(separator: ", ")
        return "[\(supportedTypes)]"
    }
}
