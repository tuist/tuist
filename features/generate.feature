Feature: Generate a new project using Tuist

  Scenario: The project is an iOS application with tests (ios_app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_tests into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests
    Then I should be able to test the scheme AppUITests
    Then I should be able to build the scheme App-Manifest

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme Framework1
    Then I should be able to test the scheme Framework1Tests
    Then I should be able to build the scheme Framework2
    Then I should be able to test the scheme Framework2Tests
    Then I should be able to build the scheme MainApp-Manifest
    Then I should be able to build the scheme Framework1-Manifest
    Then I should be able to build the scheme Framework2-Manifest

  Scenario: The project is a directory without valid manifest file (invalid_workspace_manifest_name)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture invalid_workspace_manifest_name into the working directory
    Then tuist generates reports error "❌ Error: Manifest not found at path ${ARG_PATH}"

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_libraries)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_libraries into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme A
    Then I should be able to test the scheme ATests
    Then I should be able to build the scheme B
    Then I should be able to test the scheme BTests

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme A
    Then I should be able to test the scheme ATests
    Then I should be able to build the scheme B
    Then I should be able to test the scheme BTests

Scenario: The project is an iOS application with a target dependency and transitive framework dependency (ios_app_with_transitive_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_transitive_framework into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'Framework1' with architecture 'arm64'
    Then the product 'App.app' with destination 'Debug-iphoneos' contains the framework 'Framework2' without architecture 'x86'
    Then I should be able to build the scheme Framework1

Scenario: The project is an iOS application that has resources (ios_app_with_framework_and_resources)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_and_resources into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
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

Scenario: The project is an iOS application with frameworks and tests (ios_app_with_framework_linking_static_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_linking_static_framework into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App
    Then the product 'App.app' with destination 'Debug-iphoneos' contains resource 'Frameworks/Framework1.framework/Framework1'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework2.framework/Framework2'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework3.framework/Framework3'
    Then the product 'App.app' with destination 'Debug-iphoneos' does not contain resource 'Frameworks/Framework4.framework/Framework4'
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme Framework1
    Then I should be able to test the scheme Framework1Tests
    Then I should be able to build the scheme Framework2
    Then I should be able to test the scheme Framework2Tests
    Then I should be able to build the scheme Framework3
    Then I should be able to test the scheme Framework3Tests
    Then I should be able to build the scheme Framework4
    Then I should be able to test the scheme Framework4Tests

Scenario: The project is an iOS application that has resources (ios_app_with_custom_scheme)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_custom_scheme into the working directory
    Then tuist generates the project
    Then I should be able to build the scheme App-Debug
    Then I should be able to build the scheme App-Release
    Then I should be able to build the scheme App-Local
    Then I should be able to test the scheme AppTests
    Then I should be able to build the scheme Framework1
    Then I should be able to test the scheme Framework1Tests
    Then I should be able to build the scheme Framework2
    Then I should be able to test the scheme Framework2Tests

Scenario: The project is an iOS application that has multiple dependencies (ios_app_with_multiple_dependencies)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_multiple_dependencies into the working directory
    Then tuist regenerates the project 5 times and comapre hashes of the generated project file "App/MainApp.xcodeproj/project.pbxproj"