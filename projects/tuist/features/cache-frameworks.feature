Feature: Focuses projects with pre-compiled cached xcframeworks

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache
    When tuist focuses the target MyApp
    Then MyApp links the framework MyAppKit from the cache
    Then MyApp links the framework MyAppUI from the cache
    Then I should be able to build for iOS the scheme MyApp
    Then I should be able to test for iOS the scheme MyAppTests

  Scenario: The project is an iOS application with a target dependency and transitive framework dependency (ios_app_with_transitive_project)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_transitive_project into the working directory
    Then tuist warms the cache
    When tuist focuses the target App
    Then I should be able to build for iOS the scheme App

  Scenario: The project is an iOS application with custom configuration and cache profile (ios_app_with_custom_configuration)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_custom_configuration into the working directory
    Then tuist warms the cache with Simulator profile
    When tuist focuses the target App with Simulator profile
    Then I should be able to build for iOS the scheme App

  Scenario: The project is an application (ios_workspace_with_microfeature_architecture)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    Then tuist warms the cache of Data
    When tuist focuses the target Data
    Then I should be able to build for iOS the scheme Data
