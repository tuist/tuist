Feature: Generate a new project using Tuist (suite 1)

  Scenario: The project is an iOS application with tests (ios_app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_tests into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to test for iOS the scheme AppUITests

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    Then I should be able to test for iOS the scheme Framework1
    Then I should be able to build for iOS the scheme Framework2-iOS
    Then I should be able to build for macOS the scheme Framework2-macOS
    Then I should be able to test for iOS the scheme Framework2Tests
    Then I should be able to build for iOS the scheme Framework1
    Then the product 'Framework1.framework' with destination 'Debug-iphonesimulator' contains the Info.plist key 'Test'

  Scenario: The project is an iOS application with headers (ios_app_with_headers)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_headers into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for iOS the scheme Framework1-iOS
    Then I should be able to build for macOS the scheme Framework1-macOS
    Then I should be able to test for iOS the scheme Framework1Tests

  Scenario: The project is a directory without valid manifest file (invalid_workspace_manifest_name)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture invalid_workspace_manifest_name into the working directory
    Then tuist generate yields error "Manifest not found at path ${ARG_PATH}"
