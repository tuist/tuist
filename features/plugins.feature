Feature: Generate a new project using Tuist with a plugin.

  Scenario: The project is an iOS application with plugins (app_with_plugins)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_plugins into the working directory
    Then tuist does fetch
    Then tuist generates the project
    Then I should be able to build for iOS the scheme TuistPluginTest
