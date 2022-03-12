Feature: Generate a new project using Tuist (suite 3)

Scenario: The project is an iOS application with frameworks and tests (ios_app_with_framework_linking_static_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_linking_static_framework into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'Frameworks/Framework1.framework/Framework1'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain resource 'Frameworks/Framework2.framework/Framework2'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain resource 'Frameworks/Framework3.framework/Framework3'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain resource 'Frameworks/Framework4.framework/Framework4'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for iOS the scheme Framework1
    Then I should be able to test for iOS the scheme Framework1
    Then I should be able to build for iOS the scheme Framework2
    Then I should be able to test for iOS the scheme Framework2
    Then I should be able to build for iOS the scheme Framework3
    Then I should be able to build for iOS the scheme Framework4

Scenario: The project is an iOS application that has resources (ios_app_with_custom_scheme)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_custom_scheme into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App-Debug
    Then I should be able to build for iOS the scheme App-Release
    Then I should be able to build for iOS the scheme App-Local
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for iOS the scheme Framework1
    Then I should be able to test for iOS the scheme Framework1
    Then I should be able to build for iOS the scheme Framework2
    Then I should be able to test for iOS the scheme Framework2
    Then I should be able to build for iOS the scheme Workspace-App
    Then I should be able to test for iOS the scheme Workspace-App
    Then I should be able to test for iOS the scheme Workspace-App-With-TestPlans
    Then I should be able to build for iOS the scheme Workspace-Framework
    Then I should be able to test for iOS the scheme Workspace-Framework

Scenario: The project is an iOS application with local Swift package (ios_app_with_local_swift_package)
  Given that tuist is available
  And I have a working directory
  Then I copy the fixture ios_app_with_local_swift_package into the working directory
  Then tuist generates the project
  Then I should be able to build for iOS the scheme App
  Then I should be able to test for iOS the scheme App

Scenario: The project is an iOS application with multiple configurations (ios_app_with_multi_configs)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_multi_configs into the working directory
    Then tuist generates the project
    Then the scheme App has a build setting CUSTOM_FLAG with value "Debug" for the configuration Debug
    Then the scheme App has a build setting CUSTOM_FLAG with value "Beta" for the configuration Beta
    Then the scheme App has a build setting CUSTOM_FLAG with value "Release" for the configuration Release
    Then the scheme Framework2 has a build setting CUSTOM_FLAG with value "Debug" for the configuration Debug
    Then the scheme Framework2 has a build setting CUSTOM_FLAG with value "Target.Beta" for the configuration Beta
    Then the scheme Framework2 has a build setting CUSTOM_FLAG with value "Release" for the configuration Release
    Then I should be able to archive for iOS the scheme App
    Then I should be able to analyze for iOS the scheme App
