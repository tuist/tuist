Feature: Tests projects using Tuist test
  Scenario: The project is an application with tests (app_with_test_plan)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_test_plan into the working directory
    Then tuist generates the project
    Then tuist tests the project
    Then tuist tests the scheme App using test plan All from the project
    Then tuist tests the scheme App using test plan All testing AppTest/AppTests/test_twoPlusTwo_isFour from the project
