Feature: Generate a new project using Tuist (suite 7)

Scenario: The project is an macOS command line tool without any dependencies (command_line_tool_basic)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_basic into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool

Scenario: The project is an macOS command line tool with static dependencies (command_line_tool_with_static_dependencies)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_with_static_dependencies into the working directory
    Then tuist generates the project
    Then I should be able to build for macOS the scheme CommandLineTool
    
Scenario: The project is an macOS command line tool with dynamic dependencies (command_line_tool_with_dynamic_dependencies)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_with_dynamic_dependencies into the working directory
    Then tuist lints the project and fails
