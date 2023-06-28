Feature: Generate a new project using Tuist (suite 4)

Scenario: The project is an iOS application with an incompatible Xcode version (ios_app_with_incompatible_xcode)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_incompatible_xcode into the working directory
    Then tuist generate yields error "The selected Xcode version is ${XCODE_VERSION}, which is not compatible with this project's Xcode version requirement of 3.2.1."

Scenario: The project is an iOS application with target actions
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_actions into the working directory
    Then tuist generates the project
    Then in project App the target App should have the build phase Tuist in the first position
    Then in project App the target App should have the build phase Rocks in the last position
    Then in project App the target App should have the build phase PhaseWithDependency with a dependency file named $TEMP_DIR/dependencies.d
    Then in project AppWithSpace the target AppWithSpace should have the build phase Run script in the first position
    Then I should be able to build for iOS the scheme App
    Then I should be able to build for iOS the scheme AppWithSpace

Scenario: The project is an iOS application with target actions with build variable
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_build_variables into the working directory
    Then tuist generates the project
    Then in project App the target App should have the build phase Tuist in the first position
    Then in project App in the target App the build phase in the first position should have $(DERIVED_FILE_DIR)/output.txt as an output path
    Then tuist warms the cache
    Then I should be able to build for iOS the scheme App

Scenario: The project is an iOS application with remote Swift package (ios_app_with_remote_swift_package)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_remote_swift_package into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App

Scenario: The project is a visionOS application with remote Swift package (visionos_app)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture visionos_app into the working directory
    Then tuist generates the project
    # TODO: Uncomment when xcode 15 ships
    # Then I should be able to build for visionOS the scheme App
    # Then I should be able to test for visionOS the scheme App

Scenario: The project is an iOS application with remote binary Swift package (ios_app_with_local_binary_swift_package)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_local_binary_swift_package into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App

Scenario: The project is an iOS application with extensions (ios_app_with_extensions)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_extensions into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'StickersPackExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'NotificationServiceExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extension 'NotificationServiceExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' contains extensionKit extension 'AppIntentExtension'
    Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers

Scenario: The project is a tvOS application with extensions (tvos_app_with_extensions)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture tvos_app_with_extensions into the working directory
    Then tuist generates the project
    Then I should be able to build for tvOS the scheme App
    Then the product 'App.app' with destination 'Debug-appletvsimulator' contains extension 'TopShelfExtension'
    Then the product 'App.app' with destination 'Debug-appletvsimulator' does not contain headers
