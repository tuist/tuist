Feature: Generate a new project using Tuist (suite 2)

  Scenario: The project is an iOS application with SDK dependencies (ios_app_with_sdk)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_sdk into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for macOS the scheme MacFramework
    Then I should be able to build for iOS the scheme StaticFramework
    Then I should be able to build for tvOS the scheme TVFramework

  Scenario: The project is an iOS application that has resources (ios_app_with_framework_and_resources)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_and_resources into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'tuist.png'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'Examples/item.json'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'Examples/list.json'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'Assets.car'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'resource.txt'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'en.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'fr.lproj/Greetings.strings'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'resource_without_extension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain resource 'do_not_include.dat'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'StaticFrameworkResources.bundle'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework2Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework3Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework4Resources.bundle'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
    Then the product 'StaticFrameworkResources.bundle' with destination 'Debug-iphonesimulator' contains resource 'tuist-bundle.png'
    Then the product 'StaticFramework2Resources.bundle' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework2Resources-tuist.png'
    Then the product 'StaticFramework3Resources.bundle' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework3Resources-tuist.png'
    Then the product 'StaticFramework4Resources.bundle' with destination 'Debug-iphonesimulator' contains resource 'StaticFramework4Resources-tuist.png'
    Then a file App/Derived/Sources/Bundle+App.swift exists
    Then a file App/Derived/Sources/Strings+App.swift exists
    Then a file App/Derived/Sources/Assets+App.swift exists
    Then a file App/Derived/Sources/Fonts+App.swift exists
    Then a file App/Derived/Sources/Plists+App.swift exists
    Then a file StaticFramework3/Derived/Sources/Assets+StaticFramework3.swift exists
