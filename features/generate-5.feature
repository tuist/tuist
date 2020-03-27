Feature: Generate a new project using Tuist (suite 3)

Scenario: The project is an iOS application with watch app (ios_app_with_watchapp2)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_watchapp2 into the working directory
    Then tuist generates the project
    Then I should be able to build for watchOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Watch/WatchApp.app'
    Then the product 'WatchApp.app' with destination 'Debug-watchos' contains extension 'WatchAppExtension'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain headers
    Then the product 'WatchApp.app' with destination 'Debug-watchos' does not contain headers

Scenario: The project is an iOS application with xcframeworks (ios_app_with_xcframeworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_xcframeworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'MyFramework' with architecture 'arm64'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain headers


Scenario: The project is an iOS application with a deprecated configuration name (app_with_old_config_name)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_old_config_name into the working directory
    Then tuist generates the project