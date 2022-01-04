Feature: Initialize a new project using Tuist

  Scenario: The project is a compilable macOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a macos application named Test
    Then tuist generates the project
    Then I should be able to build for macOS the scheme Test

  Scenario: The project is a compilable iOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a ios application named My-App
    Then tuist generates the project
    Then I should be able to build for iOS the scheme MyApp

  Scenario: The project is a compilable tvOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a tvos application named TvApp
    Then tuist generates the project
    Then I should be able to build for tvOS the scheme TvApp

  Scenario: The project is a compilable SwiftUI iOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a ios application named MyApp with swiftui template
    Then tuist generates the project
    Then I should be able to build for iOS the scheme MyApp

  Scenario: The project is a compilable SwiftUI macOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a macos application named Test with swiftui template
    Then tuist generates the project
    Then I should be able to build for macOS the scheme Test

  Scenario: The project is a compilable SwiftUI tvOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a tvos application named TvApp with swiftui template
    Then tuist generates the project
    Then I should be able to build for tvOS the scheme TvApp

  Scenario: The project is a CLI project initialized from a template in a different repository
    Given that tuist is available
    And I have a working directory
    When I initialize a project from the template https://github.com/tuist/ExampleTuistTemplate.git
    Then tuist builds the project
    # Then I should be able to build for tvOS the scheme TvApp
