Feature: Build projects using Tuist build
  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available
    And I have a working directory
    When I initialize a ios application named MyApp
    Then tuist generates the project
    Then tuist builds the project
    Then tuist builds the scheme MyApp from the project
    Then tuist builds the scheme MyApp and configuration Debug from the project

  Scenario: The project is an application with framework and tests (app_with_framework_and_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_framework_and_tests into the working directory
    Then tuist generates the project
    Then tuist builds the project
    Then tuist builds the scheme App from the project
    Then tuist builds the scheme AppCustomScheme from the project
    Then tuist builds the scheme App-Workspace from the project

  Scenario: The project is an application with tests (app_with_tests)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tests into the working directory
    Then tuist generates the project
    Then tuist builds the project
    Then tuist builds the scheme App from the project
    Then tuist builds the scheme App-Workspace-iOS from the project
    Then tuist builds the scheme App-Workspace-macOS from the project
    Then tuist builds the scheme App-Workspace-tvOS from the project

  Scenario: The project is an iOS application with custom configuration (ios_app_with_custom_configuration) and tuist builds configurations to custom directory
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_custom_configuration into the working directory
    Then tuist generates the project
    Then tuist builds the scheme App and configuration debug from the project to output path Builds
    Then a directory Builds/debug-iphonesimulator/App.app exists
    Then a directory Builds/debug-iphonesimulator/App.swiftmodule exists
    Then a directory Builds/debug-iphonesimulator/FrameworkA.framework exists
    Then tuist builds the scheme App and configuration release from the project to output path Builds
    Then a directory Builds/debug-iphonesimulator/App.app exists
    Then a directory Builds/debug-iphonesimulator/App.swiftmodule exists
    Then a directory Builds/debug-iphonesimulator/FrameworkA.framework exists
    Then a directory Builds/release-iphonesimulator/App.app exists
    Then a directory Builds/release-iphonesimulator/App.app.dSYM exists
    Then a directory Builds/release-iphonesimulator/App.swiftmodule exists
    Then a directory Builds/release-iphonesimulator/FrameworkA.framework exists
    Then a directory Builds/release-iphonesimulator/FrameworkA.framework.dSYM exists
