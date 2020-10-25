Feature: Tests projects using Tuist test
  Scenario: The project is an application with tests (app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist generates the project
    Then tuist tests the project
    Then tuist tests the scheme AppTests from the project
    Then tuist tests the scheme MacFrameworkTests from the project
    Then tuist tests the scheme App and configuration Debug from the project