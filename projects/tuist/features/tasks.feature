Feature: Run tasks
  Scenario: The project is an application with tasks (app_with_tasks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_tasks into the working directory
    Then tuist runs a task create-file
    Then content of a file named file.txt should be equal to File created with a task