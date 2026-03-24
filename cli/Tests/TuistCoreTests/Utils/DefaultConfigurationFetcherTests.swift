import Foundation
import Path
import Testing
import TuistTesting
import XcodeGraph

@testable import TuistCore

struct DefaultConfigurationFetcherTests {
    let subject: DefaultConfigurationFetcher

    init() {
        subject = DefaultConfigurationFetcher()
    }

    @Test func fetch_throws_an_error_when_debug_configuration_not_found() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project.test(settings: Settings(configurations: [:])),
        ])

        // When/Then
        #expect(throws: DefaultConfigurationFetcherError.debugBuildConfigurationNotFound) {
            try subject.fetch(configuration: nil, defaultConfiguration: nil, graph: graph)
        }
    }

    @Test func fetch_returns_the_first_debug_configuration_found() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Development", variant: .debug): .test()])),
        ])

        // When
        let got = try subject.fetch(configuration: nil, defaultConfiguration: nil, graph: graph)

        // Then
        #expect(got == "Development")
    }

    @Test func fetch_returns_the_configuration_if_the_configuration_exists_in_the_project() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        let got = try subject.fetch(configuration: "Dev", defaultConfiguration: nil, graph: graph)

        // Then
        #expect(got == "Dev")
    }

    @Test func fetch_throws_an_error_when_the_configuration_passed_points_to_a_non_existing_configuration() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        #expect(throws: DefaultConfigurationFetcherError.configurationNotFound("Debug", available: ["Dev"])) {
            try subject.fetch(configuration: "Debug", defaultConfiguration: nil, graph: graph)
        }
    }

    @Test func fetch_returns_the_default_configuration_if_the_configuration_exists_in_the_project() throws {
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
            defaultConfiguration: "Release",
            graph: graph
        )

        // Then
        #expect(got == "Release")
    }

    @Test func fetch_returns_the_configuration_if_the_configuration_and_default_configuration_exist_in_the_project() throws {
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
            defaultConfiguration: "Release",
            graph: graph
        )

        // Then
        #expect(got == "Dev")
    }

    @Test func fetch_throws_an_error_when_the_default_configuration_passed_points_to_a_non_existing_configuration() throws {
        // Given
        let graph = Graph.test(projects: [
            try AbsolutePath(validating: "/project-a"): Project
                .test(settings: Settings(configurations: [BuildConfiguration(name: "Dev", variant: .debug): .test()])),
        ])

        // When
        #expect(throws: DefaultConfigurationFetcherError.defaultConfigurationNotFound("Debug", available: ["Dev"])) {
            try subject.fetch(
                configuration: nil,
                defaultConfiguration: "Debug",
                graph: graph
            )
        }
    }
}
