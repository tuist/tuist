Feature: Tests projects using Tuist test
  Scenario: The project is an application with tests (app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist generates the project
    Then tuist tests the project
    Then tuist tests the scheme App-Project-iOS from the project
    Then tuist tests the scheme App-Project-macOS from the project
    Then tuist tests the scheme App-Project-tvOS from the project
    Then tuist tests the scheme AppTests from the project
    Then tuist tests the scheme MacFrameworkTests from the project
    Then tuist tests the scheme App and configuration Debug from the project

  Scenario: The project is an application with framework and tests (app_with_framework_and_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_framework_and_tests into the working directory
    Then tuist tests the project
    Then tuist tests the scheme App from the project
    Then tuist tests the scheme App-Project from the project

  Scenario: The project is an application with tests (app_with_tests)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist tests the project with automation path at Automation
    Then project contains App-Project-iOS scheme
    Then generated project is deleted
    Then tuist tests the project with automation path at Automation
    Then project does not contain App-Project-iOS scheme
    Then generated project is deleted
    Then I add an empty line at the end of the file Targets/App/Sources/AppDelegate.swift
    Then tuist tests the project with automation path at Automation
    Then project contains App-Project-iOS scheme
