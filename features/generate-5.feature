Feature: Generate a new project using Tuist (suite 5)

Scenario: The project is an iOS application with watch app (ios_app_with_watchapp2)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_watchapp2 into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'Watch/WatchApp.app'
    Then the product 'WatchApp.app' with destination 'Debug-watchsimulator' contains extension 'WatchAppExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
    Then the product 'WatchApp.app' with destination 'Debug-watchsimulator' does not contain headers

Scenario: The project contains an invalid manifest and tuist should surface compilation issues (invalid_manifest)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture invalid_manifest into the working directory
    Then tuist generate yields error "error: expected ',' separator"

Scenario: The project contains a project with a large manifest (ios_app_large)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_large into the working directory
    Then tuist generates the project

Scenario: The project contains an circular dependency (ios_workspace_with_dependency_cycle)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_dependency_cycle into the working directory
    Then tuist generate yields error "Found circular dependency between targets"