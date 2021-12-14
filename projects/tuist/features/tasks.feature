Feature: Run tasks
  Scenario: The project is an application with plugins (app_with_plugins)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_plugins into the working directory
    Then tuist does fetch
    Then current directory is added to PATH
    Then tuist runs create-file with the current directory
    Then content of a file named plugin-file.txt should be equal to File created with a plugin
    Then tuist runs inspect-graph
