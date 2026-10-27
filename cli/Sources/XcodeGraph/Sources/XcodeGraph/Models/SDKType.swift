import Foundation

public enum SDKType: CaseIterable, Equatable {
    case framework
    case library
    case swiftLibrary

    public static var supportedTypesDescription: String {
        let supportedTypes = allCases
            .map {
                switch $0 {
                case .framework:
                    return ".framework"
                case .library, .swiftLibrary:
                    return ".tbd"
                }
            }
            .joined(separator: ", ")
        return "[\(supportedTypes)]"
    }
}
