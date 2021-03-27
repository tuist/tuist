Feature: Build projects using Tuist build
  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available
    And I have a working directory
    When I initialize a ios application named MyApp
    Then tuist builds the project
    Then tuist builds the scheme MyApp from the project
    Then tuist builds the scheme MyApp and configuration Debug from the project

  Scenario: The project is an application with framework and tests (app_with_framework_and_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_framework_and_tests into the working directory
    Then tuist builds the project
    Then tuist builds the scheme App from the project
    Then tuist builds the scheme AppCustomScheme from the project
    Then tuist builds the scheme App-Project from the project

  Scenario: The project is an application with tests (app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist builds the project
    Then tuist builds the scheme App from the project
    Then tuist builds the scheme App-Project-iOS from the project
    Then tuist builds the scheme App-Project-macOS from the project
    Then tuist builds the scheme App-Project-tvOS from the project