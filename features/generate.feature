Feature: Generate a new project using Tuist

  Scenario: The project is an iOS application with tests (app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests


  Scenario: The project is an iOS application with frameworks and tests (app_with_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme Framework1
    Then I should be able to test the scheme Framework1Tests
    Then I should be able to build the scheme Framework2
    Then I should be able to test the scheme Framework2Tests


  Scenario: The project is a directory without valid manifest file (invalid_manifest)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture invalid_manifest into the working directory
    Then tuist generates reports error "❌ Error: Couldn't find manifest at path: '${ARG_PATH}'"
