Feature: Manipulate a project using Tuist with a helper plugin and be able to import it in all supported manifest types.

  Scenario: The project is an iOS application (app_with_git_helper_plugin)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_git_helper_plugin into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
