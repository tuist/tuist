import Foundation
import TSCBasic
import TuistGraph

extension DependenciesGraph {
    /// A snapshot of `graph.json` file.
    public static var testJson: String {
        """
        {
          "externalDependencies": [
            "ios",
            {
              "RxSwift": [
                {
                  "xcframework": {
                    "path": "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
                  }
                }
              ]
            }
          ],
          "externalProjects": []
        }
        """
    }

    /// A snapshot of `Dependencies.swift` file.
    public static var testDependenciesFile: String {
        """
        import ProjectDescription

        let dependencies = Dependencies(
            carthage: [
                .github(path: "RxSwift/RxSwift", requirement: .exact("5.0.4")),
            ],
            platforms: [.iOS]
        )
        """
    }

    public static func test(
        externalDependencies: [Platform: [String: [TargetDependency]]] = [:],
        externalProjects: [AbsolutePath: Project] = [:]
    ) -> Self {
        .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }

    public static func testXCFramework(
        name: String = "Test",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
        platforms: Set<Platform>
    ) -> DependenciesGraph {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [name: [.xcframework(path: path)]]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func test(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "Tuist": [
                    .project(
                        target: self.resolveTargetName(targetName: "Tuist", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func aDependency(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "ALibrary": [
                    .project(
                        target: self.resolveTargetName(targetName: "ALibrary", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func anotherDependency(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "AnotherLibrary": [
                    .project(
                        target: self
                            .resolveTargetName(targetName: "AnotherLibrary", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func alamofire(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "Alamofire": [
                    .project(
                        target: self.resolveTargetName(targetName: "Alamofire", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func googleAppMeasurement(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "GoogleAppMeasurement": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GoogleAppMeasurementTarget",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
                "GoogleAppMeasurementWithoutAdIdSupport": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func googleUtilities(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "GULAppDelegateSwizzler": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GULAppDelegateSwizzler",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
                "GULMethodSwizzler": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GULMethodSwizzler",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
                "GULNSData": [
                    .project(
                        target: self.resolveTargetName(targetName: "GULNSData", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
                "GULNetwork": [
                    .project(
                        target: self.resolveTargetName(targetName: "GULNetwork", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    public static func nanopb(
        packageFolder: AbsolutePath,
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "nanopb": [
                    .project(
                        target: self.resolveTargetName(targetName: "nanopb", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }
}

// MARK: - Helpers

extension DependenciesGraph {
    fileprivate static func resolveTargetName(targetName: String, for platform: Platform, addSuffix: Bool) -> String {
        addSuffix ? "\(targetName)_\(platform.rawValue)" : targetName
    }
}
