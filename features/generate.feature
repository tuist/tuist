Feature: Generate a new project using Tuist

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
    Then the product 'Framework1.framework' with destination 'Debug-iphoneos' contains the Info.plist key 'Test'

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
    Then tuist generate yields error "Error: Manifest not found at path ${ARG_PATH}"

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_libraries)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_libraries into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for iOS the scheme A
    Then I should be able to test for iOS the scheme ATests
    Then I should be able to build for iOS the scheme B
    Then I should be able to test for iOS the scheme BTests

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_library_and_package)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_library_and_package into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for iOS the scheme A
    Then I should be able to test for iOS the scheme ATests
    Then I should be able to build for iOS the scheme B
    Then I should be able to test for iOS the scheme BTests

  Scenario: The project is an iOS application with SDK dependencies (ios_app_with_sdk)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_sdk into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for macOS the scheme MacFramework
    Then I should be able to build for iOS the scheme StaticFramework
    Then I should be able to test for iOS the scheme StaticFrameworkTests
    Then I should be able to build for tvOS the scheme TVFramework

Scenario: The project is an iOS application with a target dependency and transitive framework dependency (ios_app_with_transitive_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_transitive_framework into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'Framework1' with architecture 'arm64'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'Framework2' without architecture 'x86_64'
    Then I should be able to build for iOS the scheme Framework1-iOS
    Then I should be able to build for iOS the scheme Framework1-macOS
    Then I should be able to build for iOS the scheme Framework1Tests-iOS
    Then I should be able to build for macOS the scheme Framework1Tests-macOS

Scenario: The project is an iOS application that has resources (ios_app_with_framework_and_resources)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_and_resources into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'tuist.png'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Examples/item.json'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Examples/list.json'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Assets.car'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'resource.txt'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'en.lproj/App.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'en.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'fr.lproj/App.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'fr.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'resource_without_extension'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'do_not_include.dat'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'StaticFrameworkResources.bundle'
    Then the product 'StaticFrameworkResources.bundle' with destination 'Debug-iphoneos' contains resource 'tuist-bundle.png'

Scenario: The project is an iOS application with frameworks and tests (ios_app_with_framework_linking_static_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_linking_static_framework into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Frameworks/Framework1.framework/Framework1'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework2.framework/Framework2'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework3.framework/Framework3'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework4.framework/Framework4'
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for iOS the scheme Framework1
    Then I should be able to test for iOS the scheme Framework1Tests
    Then I should be able to build for iOS the scheme Framework2
    Then I should be able to test for iOS the scheme Framework2Tests
    Then I should be able to build for iOS the scheme Framework3
    Then I should be able to test for iOS the scheme Framework3Tests
    Then I should be able to build for iOS the scheme Framework4
    Then I should be able to test for iOS the scheme Framework4Tests

Scenario: The project is an iOS application that has resources (ios_app_with_custom_scheme)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_custom_scheme into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App-Debug
    Then I should be able to build for iOS the scheme App-Release
    Then I should be able to build for iOS the scheme App-Local
    Then I should be able to test for iOS the scheme AppTests
    Then I should be able to build for iOS the scheme Framework1
    Then I should be able to test for iOS the scheme Framework1Tests
    Then I should be able to build for iOS the scheme Framework2
    Then I should be able to test for iOS the scheme Framework2Tests

Scenario: The project is an iOS application with local Swift package (ios_app_with_local_swift_package)
  Given that tuist is available
  And I have a working directory
  Then I copy the fixture ios_app_with_local_swift_package into the working directory
  Then tuist generates the project
  Then I should be able to build for iOS the scheme App
  Then I should be able to test for iOS the scheme AppTests
  Then I should be able to build for iOS the scheme LibraryA
  Then I should be able to build for iOS the scheme LibraryB

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

Scenario: The project is an iOS application with CocoaPods dependencies (ios_app_with_pods)
  Given that tuist is available
  And I have a working directory
  Then I copy the fixture ios_app_with_pods into the working directory
  Then tuist generates the project
  Then I should be able to build for iOS the scheme App

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
    Then the target App should have the build phase Tuist in the first position
    Then the target App should have the build phase Rocks in the last position

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
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'RxSwift' without architecture 'armv7'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'RxSwift' with architecture 'arm64'

Scenario: The project is an iOS application with extensions (ios_app_with_extensions)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_extensions into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains extension 'StickersPackExtension'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains extension 'NotificationServiceExtension' 
    Then the product 'App.app' with destination 'Debug-iphoneos' contains extension 'NotificationServiceExtension' 

Scenario: The project is an iOS application with watch app (ios_app_with_watchapp2)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_watchapp2 into the working directory
    Then tuist generates the project
    Then I should be able to build for watchOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Watch/WatchApp.app'
    Then the product 'WatchApp.app' with destination 'Debug-watchos' contains extension 'WatchAppExtension' 

Scenario: The project is an iOS application with Xcframeworks (ios_app_with_xcframeworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_xcframeworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'MyFramework' with architecture 'arm64'
