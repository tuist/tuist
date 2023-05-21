import Foundation
import MyStaticLibrary
import StaticFrameworkB

public final class StaticFrameworkAComponent {
    public let name = "StaticFrameworkAComponent"
    private let staticLibraryComponent = MyStaticLibraryComponent()
    private let staticFrameworkBComponent = StaticFrameworkBComponent()

    public init() {}

    public func composedName() -> String {
        "\(name) > \(staticLibraryComponent.name) > \(staticFrameworkBComponent.composedName())"
    }
}
