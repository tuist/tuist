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

  Scenario: The project is an application with transitive local Swift packages (ios_app_with_transitive_local_packages)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_app_with_transitive_local_packages into the working directory
    And tuist warms the cache
    When tuist generates a project with cached targets at Projects/App
    Then App links the xcframework Framework
    Then App embeds the xcframework Framework
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests