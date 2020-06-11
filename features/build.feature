Feature: Build projects using Tuist build

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    When I initialize a ios application named MyApp
    Then tuist builds the project
    Then tuist builds the scheme MyApp from the project
    Then tuist builds the scheme MyApp and configuration Debug from the project