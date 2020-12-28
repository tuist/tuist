Feature: Generate a new project using Tuist (suite 1)

  Scenario: The project is an iOS application with tests (app_with_development_region_config)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_development_region_config into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the Info.plist key 'CFBundleDevelopmentRegion' with value 'de'

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
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to test for iOS the scheme Framework1Tests
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
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for iOS the scheme Framework1-iOS
    Then I should be able to build for macOS the scheme Framework1-macOS
    Then I should be able to test for iOS the scheme Framework1Tests

  Scenario: The project is a directory without valid manifest file (invalid_workspace_manifest_name)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture invalid_workspace_manifest_name into the working directory
    Then tuist generate yields error "Manifest not found at path ${ARG_PATH}"

  Scenario: The project is an iOS application with signing (ios_app_with_signing)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_signing into the working directory
    Then tuist generates the project
    Then the scheme SignApp has a build setting CODE_SIGN_IDENTITY with value Apple Development: Marek Fort (54GSF6G47V) for the configuration Debug
    Then the scheme SignApp has a build setting PROVISIONING_PROFILE_SPECIFIER with value d34fb066-f494-4d85-a556-d469c2196f46 for the configuration Debug
    Then the scheme SignApp has a build setting CODE_SIGN_IDENTITY with value Apple Development: Marek Fort (54GSF6G47V) for the configuration Release
    Then the scheme SignApp has a build setting PROVISIONING_PROFILE_SPECIFIER with value 76a7d75c-01d4-4c7f-9140-1d829227883a for the configuration Release
    Then the scheme SignApp has a build setting PRODUCT_BUNDLE_IDENTIFIER with value team.io.tuist.debug for the configuration Debug
    Then the scheme SignApp has a build setting PRODUCT_BUNDLE_IDENTIFIER with value team.io.tuist.release for the configuration Release
    Then the scheme AppA has a build setting CODE_SIGN_IDENTITY with value iPhone Developer: Christoph Lederer (F2X7FM3XMV) for the configuration Debug
    Then the scheme AppA has a build setting PROVISIONING_PROFILE_SPECIFIER with value 7fcc4b2f-adbf-4a86-be34-fc8bc4f1ad7 for the configuration Debug
    Then the scheme AppA has a build setting PRODUCT_BUNDLE_IDENTIFIER with value io.tuist.test.appA for the configuration Debug
    Then the scheme AppB has a build setting CODE_SIGN_IDENTITY with value iPhone Developer: Christoph Lederer (F2X7FM3XMV) for the configuration Debug
    Then the scheme AppB has a build setting PROVISIONING_PROFILE_SPECIFIER with value 59024d29-40ec-4719-8800-7b539ed98051 for the configuration Debug
    Then the scheme AppB has a build setting PRODUCT_BUNDLE_IDENTIFIER with value io.tuist.test.appB for the configuration Debug
