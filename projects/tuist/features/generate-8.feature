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