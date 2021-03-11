Feature: Setup project tools using Tuist

  Scenario: The project is an iOS application with a custom test tool (ios_app_with_setup)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_setup into the working directory
    Then tuist sets up the project
    Then I should have /tmp/my_test_tool installed
    Then a directory Carthage/Build/Alamofire.xcframework exists