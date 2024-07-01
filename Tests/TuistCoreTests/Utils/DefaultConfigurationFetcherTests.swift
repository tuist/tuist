import Foundation
import Path
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistCore

final class DefaultConfigurationFetcherTests: TuistUnitTestCase {
    private var subject: DefaultConfigurationFetcher!

    override func setUp() {
        super.setUp()
        subject = DefaultConfigurationFetcher()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_fetch_throws_an_error_when_debug_configuration_not_found() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project.test(settings: Settings(configurations: [:])),
        ])

        // When/Then
        XCTAssertThrowsSpecific(
            try subject.fetch(configuration: nil, config: .test(), graph: graph),
            DefaultConfigurationFetcherError.debugBuildConfigurationNotFound
        )
    }

    func test_fetch_returns_the_first_debug_configuration_found() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Development", variant: .debug): .test()])),
        ])

        // When
        let got = try subject.fetch(configuration: nil, config: .test(), graph: graph)

        // Then
        XCTAssertEqual(got, "Development")
    }

    func test_fetch_returns_the_configuration_if_the_configuration_exists_in_the_project() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        let got = try subject.fetch(configuration: "Dev", config: .test(), graph: graph)

        // Then
        XCTAssertEqual(got, "Dev")
    }

    func test_fetch_throws_an_error_when_the_configuration_passed_points_to_a_non_existing_configuration() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        XCTAssertThrowsSpecific(
            try subject.fetch(configuration: "Debug", config: .test(), graph: graph),
            DefaultConfigurationFetcherError.configurationNotFound("Debug", available: ["Dev"])
        )
    }

    func test_fetch_returns_the_default_configuration_if_the_configuration_exists_in_the_project() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(
                    settings: Settings(
                        configurations: [
                            BuildConfiguration(name: "Dev", variant: .debug): .test(),
                            BuildConfiguration(name: "Release", variant: .release): .test(),
                        ]
                    )
                ),
        ])

        // When
        let got = try subject.fetch(
            configuration: nil,
            config: .test(
                generationOptions: .test(
                    defaultConfiguration: "Release"
                )
            ),
            graph: graph
        )

        // Then
        XCTAssertEqual(got, "Release")
    }

    func test_fetch_returns_the_configuration_if_the_configuration_and_default_configuration_exist_in_the_project() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(
                    settings: Settings(
                        configurations: [
                            BuildConfiguration(name: "Dev", variant: .debug): .test(),
                            BuildConfiguration(name: "Release", variant: .release): .test(),
                        ]
                    )
                ),
        ])

        // When
        let got = try subject.fetch(
            configuration: "Dev",
            config: .test(
                generationOptions: .test(
                    defaultConfiguration: "Release"
                )
            ),
            graph: graph
        )

        // Then
        XCTAssertEqual(got, "Dev")
    }

    func test_fetch_throws_an_error_when_the_default_configuration_passed_points_to_a_non_existing_configuration() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        XCTAssertThrowsSpecific(
            try subject.fetch(
                configuration: nil,
                config: .test(
                    generationOptions: .test(
                        defaultConfiguration: "Debug"
                    )
                ),
                graph: graph
            ),
            DefaultConfigurationFetcherError.defaultConfigurationNotFound("Debug", available: ["Dev"])
        )
    }
}
