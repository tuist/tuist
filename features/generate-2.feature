Feature: Generate a new project using Tuist (suite 2)

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
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain headers
    Then I should be able to build for iOS the scheme AppUITests
    Then the product 'AppUITests-Runner.app' with destination 'Debug-iphoneos' does not contain the framework 'Framework2'
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
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'en.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'fr.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'resource_without_extension'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'do_not_include.dat'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'StaticFrameworkResources.bundle'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'StaticFramework2Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'StaticFramework3Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'StaticFramework4Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain headers
    Then the product 'StaticFrameworkResources.bundle' with destination 'Debug-iphoneos' contains resource 'tuist-bundle.png'
    Then the product 'StaticFramework2Resources.bundle' with destination 'Debug-iphoneos' contains resource 'StaticFramework2Resources-tuist.png'
    Then the product 'StaticFramework3Resources.bundle' with destination 'Debug-iphoneos' contains resource 'StaticFramework3Resources-tuist.png'
    Then the product 'StaticFramework4Resources.bundle' with destination 'Debug-iphoneos' contains resource 'StaticFramework4Resources-tuist.png'
    Then a file App/Derived/Sources/Bundle+App.swift exists
    Then a file App/Derived/Sources/Strings+App.swift exists
    Then a file App/Derived/Sources/Assets+App.swift exists
    Then a file App/Derived/Sources/Fonts+App.swift exists
    Then a file App/Derived/Sources/Environment.swift exists
    Then a file StaticFramework3/Derived/Sources/Assets+StaticFramework3.swift exists
