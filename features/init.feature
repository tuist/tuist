Feature: Initialize a new project using Tuist

  Scenario: The project is a compilable macOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a macos application named Test
    Then tuist generates the project
    Then I should be able to build the scheme Test

  Scenario: The project is a compilable iOS application
    Given that tuist is available
    And I have a working directory
    When I initialize a ios application named Test
    Then tuist generates the project
    Then I should be able to build the scheme Test
    Then I should have a file named Main.storyboard
