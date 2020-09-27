Feature: Generate a new project using Tuist (suite 4)

Scenario: The project is an iOS application with an incompatible Xcode version (ios_app_with_incompatible_xcode)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_incompatible_xcode into the working directory
    Then tuist generate yields error "The project, which only supports the versions of Xcode 3.2.1, is not compatible with your selected version of Xcode"

Scenario: The project is an iOS application with target actions
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_actions into the working directory
    Then tuist generates the project
    Then in project App the target App should have the build phase Tuist in the first position
    Then in project App the target App should have the build phase Rocks in the last position
    Then in project AppWithSpace the target AppWithSpace should have the build phase Run script in the first position
    Then I should be able to build for iOS the scheme App
    Then I should be able to build for iOS the scheme AppWithSpace

Scenario: The project is an iOS application with remote Swift package (ios_app_with_remote_swift_package)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_remote_swift_package into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests

Scenario: The project is an iOS application with Carthage frameworks (ios_app_with_carthage_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_carthage_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme AllTargets
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'RxSwift' without architecture 'armv7'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'RxSwift' with architecture 'x86_64'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers

Scenario: The project is an iOS application with extensions (ios_app_with_extensions)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_extensions into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'StickersPackExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'NotificationServiceExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'NotificationServiceExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
