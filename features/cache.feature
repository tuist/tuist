Feature: Generates projects with pre-compiled cached dependencies

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache
    When tuist generates a project with cached targets at Projects/MyApp
    Then MyApp links the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppSupport
    Then I should be able to build for iOS the scheme MyApp
    Then I should be able to test for iOS the scheme MyAppTests