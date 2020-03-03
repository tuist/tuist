Feature: Scaffold a project using Tuist

  Scenario: The project is an application with helpers (ios_app_with_helpers)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_app_with_helpers into the working directory
    Then tuist edits the project
    Then I should be able to build for macOS the scheme ProjectDescriptionHelpers
