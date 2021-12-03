import Foundation
import TSCBasic
import TuistGraph

extension DependenciesGraph {
    /// A snapshot of `graph.json` file.
    public static var testJson: String {
        """
        {
          "externalDependencies" : {
            "RxSwift" : [
              {
                "kind" : "xcframework",
                "path" : "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
              }
            ]
          },
          "externalProjects": []
        }
        """
    }

    public static func test(
        externalDependencies: [String: [TargetDependency]] = [:],
        externalProjects: [AbsolutePath: Project] = [:]
    ) -> Self {
        return .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }

    public static func testXCFramework(
        name: String = "Test",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework"))
    ) -> DependenciesGraph {
        return .init(
            externalDependencies: [
                name: [.xcframework(path: path)],
            ],
            externalProjects: [:]
        )
    }

    public static func test(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "Tuist": [.project(target: "Tuist", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }

    public static func aDependency(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "ALibrary": [.project(target: "ALibrary", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }

    public static func anotherDependency(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "AnotherLibrary": [.project(target: "AnotherLibrary", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }

    public static func alamofire(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "Alamofire": [.project(target: "Alamofire", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }

    public static func googleAppMeasurement(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "GoogleAppMeasurement": [.project(target: "GoogleAppMeasurementTarget", path: packageFolder)],
                "GoogleAppMeasurementWithoutAdIdSupport": [.project(
                    target: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    path: packageFolder
                )],
            ],
            externalProjects: [:]
        )
    }

    public static func googleUtilities(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "GULAppDelegateSwizzler": [.project(target: "GULAppDelegateSwizzler", path: packageFolder)],
                "GULMethodSwizzler": [.project(target: "GULMethodSwizzler", path: packageFolder)],
                "GULNSData": [.project(target: "GULNSData", path: packageFolder)],
                "GULNetwork": [.project(target: "GULNetwork", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }

    public static func nanopb(packageFolder: AbsolutePath) -> Self {
        return .init(
            externalDependencies: [
                "nanopb": [.project(target: "nanopb", path: packageFolder)],
            ],
            externalProjects: [:]
        )
    }
}
