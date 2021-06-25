import Foundation
import TSCBasic
import TuistGraph

public extension DependenciesGraph {
    /// A snapshot of `graph.json` file.
    static var testJson: String {
        """
        {
          "externalDependencies" : {
            "RxSwift" : [
              {
                "kind" : "xcframework",
                "path" : "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
              }
            ]
          }
        }
        """
    }

    static func test(externalDependencies: [String: [TargetDependency]] = [:]) -> Self {
        return .init(externalDependencies: externalDependencies)
    }

    static func testXCFramework(
        name: String = "Test",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework"))
    ) -> DependenciesGraph {
        return .init(externalDependencies: [
            name: [.xcframework(path: path)],
        ])
    }

    static func test(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "Tuist": [.project(target: "Tuist", path: packageFolder)],
        ])
    }

    static func aDependency(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "ALibrary": [.project(target: "ALibrary", path: packageFolder)],
        ])
    }

    static func anotherDependency(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "AnotherLibrary": [.project(target: "AnotherLibrary", path: packageFolder)],
        ])
    }

    static func alamofire(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "Alamofire": [.project(target: "Alamofire", path: packageFolder)],
        ])
    }

    static func googleAppMeasurement(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "GoogleAppMeasurement": [.project(target: "GoogleAppMeasurementTarget", path: packageFolder)],
            "GoogleAppMeasurementWithoutAdIdSupport": [.project(target: "GoogleAppMeasurementWithoutAdIdSupportTarget", path: packageFolder)],
        ])
    }

    static func googleUtilities(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "GULAppDelegateSwizzler": [.project(target: "GULAppDelegateSwizzler", path: packageFolder)],
            "GULMethodSwizzler": [.project(target: "GULMethodSwizzler", path: packageFolder)],
            "GULNSData": [.project(target: "GULNSData", path: packageFolder)],
            "GULNetwork": [.project(target: "GULNetwork", path: packageFolder)],
        ])
    }

    static func nanopb(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "nanopb": [.project(target: "nanopb", path: packageFolder)],
        ])
    }
}
