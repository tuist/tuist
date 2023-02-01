Feature: Generate a new project using Tuist (suite 1)

  Scenario: The project is an iOS application with tests (ios_app_with_tests)
    Given that tuist is available
    And I run a local tuist cloud server
    And I have a working directory
    Then I copy the fixture ios_app_with_tests into the working directory
    Then tuist inits new cloud project