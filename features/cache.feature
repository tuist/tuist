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

Scenario: The project is an application with templates (ios_workspace_with_microfeature_architecture)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    And tuist warms the cache
    When tuist generates a project with cached targets at App
    Then App embeds the xcframework Core
    Then App embeds the xcframework Data
    Then App embeds the xcframework FeatureContracts
    Then App embeds the xcframework UIComponents
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests

Scenario: The project is an application with templates (ios_workspace_with_microfeature_architecture_static_linking)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture_static_linking into the working directory
    And tuist warms the cache
    When tuist generates a project with cached targets at StaticApp
    Then StaticApp links the xcframework FrameworkA
    Then StaticApp does not embed any xcframeworks
    Then I should be able to build for iOS the scheme StaticApp
    Then I should be able to test for iOS the scheme StaticAppTests
