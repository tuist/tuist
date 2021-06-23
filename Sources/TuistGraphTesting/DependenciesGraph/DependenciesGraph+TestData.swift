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

    // swiftlint:disable:next function_body_length
    static func test(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "Tuist": [.project(target: "Tuist", path: packageFolder.projectPath)],
        ])
    }

    static func aDependency(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "ALibrary": [.project(target: "ALibrary", path: packageFolder.projectPath)],
        ])
    }

    static func anotherDependency(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "AnotherLibrary": [.project(target: "AnotherLibrary", path: packageFolder.projectPath)],
        ])
    }

    static func alamofire(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "Alamofire": [.project(target: "Alamofire", path: packageFolder.projectPath)],
        ])
    }

    // swiftlint:disable:next function_body_length
    static func googleAppMeasurement(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "GoogleAppMeasurement": [
                .project(target: "GoogleAppMeasurementTarget", path: packageFolder.projectPath),
            ],
            "GoogleAppMeasurementWithoutAdIdSupport": [
                .project(target: "GoogleAppMeasurementWithoutAdIdSupportTarget", path: packageFolder.projectPath),
            ],
        ])
    }

    // swiftlint:disable:next function_body_length
    static func googleUtilities(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "GULAppDelegateSwizzler": [.project(target: "GULAppDelegateSwizzler", path: packageFolder.projectPath),],
            "GULMethodSwizzler": [.project(target: "GULMethodSwizzler", path: packageFolder.projectPath),],
            "GULNSData": [.project(target: "GULNSData", path: packageFolder.projectPath),],
            "GULNetwork": [.project(target: "GULNetwork", path: packageFolder.projectPath),],
        ])
    }

    static func nanopb(packageFolder: AbsolutePath) -> Self {
        return .init(externalDependencies: [
            "nanopb": [.project(target: "nanopb", path: packageFolder.projectPath),],
        ])
    }
}

extension AbsolutePath {
    var projectPath: AbsolutePath {
        return self.appending(component: "Project.json")
    }
}
