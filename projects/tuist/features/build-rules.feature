Feature: Build projects using Tuist build
  Scenario: The project is an application with build rules (app_with_build_rules)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_build_rules into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the target App should have the build rule Process_InfoPlist.strings with pattern */InfoPlist.strings