Feature: List targets sorted by number of dependencies

  Scenario: The project is the microfeature fixture
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    Then run tuist migration list-targets for the UIComponents project in ios_workspace_with_microfeature_architecture should contain:
      """
      UIComponents - dependencies count: 1
      UIComponentsTests - dependencies count: 2
      """
    Then run tuist migration list-targets for the Core project in ios_workspace_with_microfeature_architecture should contain:
      """
      Core - dependencies count: 0
      CoreTests - dependencies count: 2
      """
    Then run tuist migration list-targets for the Data project in ios_workspace_with_microfeature_architecture should contain:
      """
      Data - dependencies count: 1
      DataTests - dependencies count: 2
      """
    