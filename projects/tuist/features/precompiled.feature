Feature: A set of tests that run with pre-compiled binaries that are only compatible with a specific version of Swift

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_frameworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for iOS the scheme A
    Then I should be able to build for iOS the scheme B
    
  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_libraries)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_libraries into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    Then I should be able to build for iOS the scheme A
    Then I should be able to build for iOS the scheme B

  Scenario: The project is an iOS application with a target dependency and transitive framework dependency (ios_app_with_transitive_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_transitive_framework into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'Framework1' with architecture 'x86_64'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'Framework2' without architecture 'arm64'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
    Then I should be able to build for iOS the scheme App
    Then the product 'AppUITests-Runner.app' with destination 'Debug-iphonesimulator' does not contain the framework 'Framework2'
    Then I should be able to build for iOS the scheme Framework1-iOS
    Then I should be able to build for macOS the scheme Framework1-macOS
    Then I should be able to build for iOS the scheme Framework1Tests-iOS
    Then I should be able to build for macOS the scheme Framework1Tests-macOS
    Then I should be able to build for iOS the scheme StaticFramework1

  Scenario: The project is an iOS application with frameworks and tests (ios_app_with_static_library_and_package)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_static_library_and_package into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    
  Scenario: The project is an iOS application with xcframeworks (ios_app_with_xcframeworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_xcframeworks into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme StaticFrameworkA
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'MyFramework' with architecture 'x86_64'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
    Then I should be able to archive for iOS the scheme App
