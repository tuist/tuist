import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistDependencies
@testable import TuistLoaderTesting
@testable import TuistPluginTesting
@testable import TuistSupportTesting

final class DependenciesServiceTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    private var pluginService: MockPluginService!

    private var subject: DependenciesService!

    override func setUp() {
        super.setUp()

        manifestLoader = MockManifestLoader()
        pluginService = MockPluginService()
        subject = DependenciesService(
            manifestLoader: manifestLoader,
            pluginService: pluginService
        )
    }

    override func tearDown() {
        subject = nil
        pluginService = nil
        manifestLoader = nil

        super.tearDown()
    }

    func test_loadDependencies() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let localSwiftPackagePath = temporaryPath.appending(component: "LocalPackage")
        let config = TuistGraph.Config.test()

        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthage: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                swiftPackageManager: .init(
                    [
                        .local(path: Path(localSwiftPackagePath.pathString)),
                        .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                    ]
                ),
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadDependencies(at: temporaryPath, using: config)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .local(path: localSwiftPackagePath),
                    .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                ],
                productTypes: [:],
                baseSettings: .init(configurations: [
                    .debug: .init(settings: [:], xcconfig: nil),
                    .release: .init(settings: [:], xcconfig: nil),
                ]),
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(got, expected)
    }

    func test_loadDependencies_with_plugins() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let localSwiftPackagePath = temporaryPath.appending(component: "LocalPackage")
        let plugins = Plugins.test()
        let config = TuistGraph.Config.test(plugins: [])

        pluginService.loadPluginsStub = { _config in
            XCTAssertEqual(config, _config)
            return plugins
        }

        manifestLoader.registerPluginsStub = { _plugins in
            XCTAssertEqual(plugins, _plugins)
        }

        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthage: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                swiftPackageManager: .init(
                    [
                        .local(path: Path(localSwiftPackagePath.pathString)),
                        .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                    ]
                ),
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadDependencies(at: temporaryPath, using: config)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .local(path: localSwiftPackagePath),
                    .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                ],
                productTypes: [:],
                baseSettings: .init(configurations: [
                    .debug: .init(settings: [:], xcconfig: nil),
                    .release: .init(settings: [:], xcconfig: nil),
                ]),
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(got, expected)
    }
}
