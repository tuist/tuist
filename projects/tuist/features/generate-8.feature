Feature: Generate a new project using Tuist (suite 8)

Scenario: The project has customized file header template (project_with_file_header_template)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture project_with_file_header_template into the working directory
    Then tuist generates the project
    Then a file App.xcodeproj/xcshareddata/IDETemplateMacros.plist exists

Scenario: The project has customized inline file header template (project_with_inline_file_header_template)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture project_with_inline_file_header_template into the working directory
    Then tuist generates the project
    Then a file App.xcodeproj/xcshareddata/IDETemplateMacros.plist exists

Scenario: The workspace has customized file header template (workspace_with_file_header_template)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture workspace_with_file_header_template into the working directory
    Then tuist generates the project
    Then a file Workspace.xcworkspace/xcshareddata/IDETemplateMacros.plist exists

Scenario: The workspace has customized inline file header template (workspace_with_inline_file_header_template)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture workspace_with_inline_file_header_template into the working directory
    Then tuist generates the project
    Then a file Workspace.xcworkspace/xcshareddata/IDETemplateMacros.plist exists

Scenario: The ios app with framework has disabled resources (ios_app_with_framework_and_disabled_resources)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_framework_and_disabled_resources into the working directory
    Then tuist generates the project
    Then a file App/Derived/Sources/Bundle+App.swift does not exist
    Then a file Framework1/Derived/Sources/Bundle+Framework1.swift does not exist
    Then a file StaticFramework/Derived/Sources/Bundle+StaticFramework.swift does not exist

Scenario: The project is a macOS app with extensions (macos_app_with_extensions)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture macos_app_with_extensions into the working directory
    Then I install the Workflow extensions SDK
    Then tuist generates the project
    Then I should be able to build for macOS the scheme App