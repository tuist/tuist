Feature: Tests projects using Tuist run
  Scenario: The project is a command line application with a runnable scheme (command_line_tool_basic)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture command_line_tool_basic into the working directory
    Then tuist runs the scheme CommandLineTool outputting to out.txt
    Then a file out.txt exists
