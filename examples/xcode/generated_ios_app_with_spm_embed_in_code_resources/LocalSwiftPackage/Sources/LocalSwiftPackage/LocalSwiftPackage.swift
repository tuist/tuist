import Foundation

public struct LocalSwiftPackage {
    public static let greeting: String = {
        let data = Data(PackageResources.greeting_txt)
        return String(decoding: data, as: UTF8.self)
    }()

    public init() {}
}
