Feature: Working with a plugin

  Scenario: The project is a tuist plugin
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture tuist_plugin into the working directory
    Then tuist builds the plugin
    Then tuist runs plugin's task tuist-create-file
    Then tuist tests the plugin
