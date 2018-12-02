Feature: Initialize a new project using Tuist

  Scenario: The project is a compilable macOS application
    Given that tuist is available
    And I have have a working directory
    When I initialize a macos application named Test
    Then I generate the project
    Then I should be able to build the scheme Test
    Then I delete the working directory