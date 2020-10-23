Feature: Focuses projects with pre-compiled cached xcframeworks

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache
    When tuist focuses the target MyApp
    Then MyApp links the framework MyAppKit
    Then MyApp links the framework MyAppUI
    Then I should be able to build for iOS the scheme MyApp
    Then I should be able to test for iOS the scheme MyAppTests