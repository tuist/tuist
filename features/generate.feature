Feature: Generate a new project using Tuist

  Scenario: The project is an iOS application with tests
    Given that tuist is available
    And I have have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests