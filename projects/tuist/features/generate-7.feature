Feature: Generate a new project using Tuist (suite 7)

Scenario: The project is a macOS command line tool without any dependencies (command_line_tool_basic)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_basic into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool

Scenario: The project is a macOS command line tool with static library (command_line_tool_with_static_library)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_with_static_library into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool

Scenario: The project is a macOS command line tool with dynamic dependencies (command_line_tool_with_dynamic_library)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_with_dynamic_library into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool

Scenario: The project is a macOS command line tool with dynamic framework (command_line_tool_with_dynamic_framework)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_with_dynamic_framework into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool

Scenario: The project is a macOS app without any dependencies (macos_app_with_copy_files)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture macos_app_with_copy_files into the working directory
    Then tuist generates the project
    Then the target App should have the build phase Copy Templates
    Then I should be able to build for macOS the scheme App

Scenario: The project is a macOS app with logs in the manifest (manifest_with_logs)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture manifest_with_logs into the working directory
    Then tuist generates the project and outputs: Target name - App
