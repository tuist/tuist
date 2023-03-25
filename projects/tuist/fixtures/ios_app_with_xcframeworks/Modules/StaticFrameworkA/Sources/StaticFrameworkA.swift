import Foundation
import MyStaticLibrary

public final class StaticFrameworkAComponent {
    public let name = "StaticFrameworkAComponent"
    private let staticLibraryComponent = MyStaticLibraryComponent()

    public init() {}

    public func composedName() -> String {
        "\(name) > \(staticLibraryComponent.name)"
    }
}
