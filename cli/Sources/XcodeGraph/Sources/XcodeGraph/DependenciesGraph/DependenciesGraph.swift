import Foundation
import Path

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable, Sendable {
    /// A dictionary where the keys are the supported platforms and the values are dictionaries where the keys are the names of
    /// dependencies, and the values are the dependencies themselves.
    public let externalDependencies: [String: [TargetDependency]]

    /// A dictionary where the keys are the folder of external projects, and the values are the projects themselves.
    public let externalProjects: [AbsolutePath: Project]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: [TargetDependency]], externalProjects: [AbsolutePath: Project]) {
        self.externalDependencies = externalDependencies
        self.externalProjects = externalProjects
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:], externalProjects: [:])
}

#if DEBUG
    extension DependenciesGraph {
        static func test(
            externalDependencies: [String: [TargetDependency]] = [:],
            externalProjects: [AbsolutePath: Project] = [:]
        ) -> Self {
            .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
        }

        public static func testXCFramework(
            name: String = "Test",
            // swiftlint:disable:next force_try
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "Test.xcframework")),
            expectedSignature: XCFrameworkSignature = .unsigned,
            status: LinkingStatus = .required
        ) -> DependenciesGraph {
            let externalDependencies = [name: [TargetDependency.xcframework(
                path: path,
                expectedSignature: expectedSignature,
                status: status
            )]]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        static func test(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "Tuist": [
                    TargetDependency.project(
                        target: "Tuist",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func aDependency(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "ALibrary": [
                    TargetDependency.project(
                        target: "ALibrary",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func anotherDependency(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "AnotherLibrary": [
                    TargetDependency.project(
                        target: "AnotherLibrary",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func alamofire(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "Alamofire": [
                    TargetDependency.project(
                        target: "Alamofire",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func googleAppMeasurement(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "GoogleAppMeasurement": [
                    TargetDependency.project(
                        target: "GoogleAppMeasurementTarget",
                        path: packageFolder
                    ),
                ],
                "GoogleAppMeasurementWithoutAdIdSupport": [
                    TargetDependency.project(
                        target: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func googleUtilities(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "GULAppDelegateSwizzler": [
                    TargetDependency.project(
                        target: "GULAppDelegateSwizzler",
                        path: packageFolder
                    ),
                ],
                "GULMethodSwizzler": [
                    TargetDependency.project(
                        target: "GULMethodSwizzler",
                        path: packageFolder
                    ),
                ],
                "GULNSData": [
                    TargetDependency.project(
                        target: "GULNSData",
                        path: packageFolder
                    ),
                ],
                "GULNetwork": [
                    TargetDependency.project(
                        target: "GULNetwork",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }

        public static func nanopb(
            packageFolder: AbsolutePath
        ) -> Self {
            let externalDependencies = [
                "nanopb": [
                    TargetDependency.project(
                        target: "nanopb",
                        path: packageFolder
                    ),
                ],
            ]

            return .init(
                externalDependencies: externalDependencies,
                externalProjects: [:]
            )
        }
    }
#endif
