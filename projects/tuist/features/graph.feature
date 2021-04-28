Feature: Generate graph
  Scenario: The project is an application (ios_workspace_with_microfeature_architecture)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    Then tuist graph
    Then I should be able to open a graph file

  Scenario: The project is an application (ios_workspace_with_microfeature_architecture)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    Then tuist graph of Data
    Then I should be able to open a graph file
