Feature: Edit an existing project using Tuist

  Scenario: The project is an application with helpers, sub projects, Config.swift and Project.swift (ios_app_with_helpers)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_helpers into the working directory
    Then tuist edits the project
    Then I should be able to build for macOS the scheme ProjectDescriptionHelpers
    Then I should be able to build for macOS the scheme AppManifests
    Then I should be able to build for macOS the scheme AppKitManifests
    Then I should be able to build for macOS the scheme AppSupportManifests
    Then I should be able to build for macOS the scheme Setup
    Then I should be able to build for macOS the scheme Config