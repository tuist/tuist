import Foundation
import MyStaticLibrary

public final class StaticFrameworkBComponent {
    public let name = "StaticFrameworkBComponent"
    private let staticLibraryComponent = MyStaticLibraryComponent()

    public init() {}

    public func composedName() -> String {
        "\(name) > \(staticLibraryComponent.name)"
    }
}
