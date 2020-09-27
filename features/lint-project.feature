Feature: Lint a project using Tuist

  Scenario: The project is an iOS application with incompatible dependencies (ios_app_with_incompatible_dependencies)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_incompatible_dependencies into the working directory
    Then tuist lints the project and fails