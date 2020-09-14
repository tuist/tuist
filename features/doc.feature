Feature: Generate documentation for a specific target using Tuist

  Scenario: The project is an application with frameworks (ios_app_with_frameworks)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_frameworks into the working directory
    Then I should be able to access the documentation of target 'Framework1'
