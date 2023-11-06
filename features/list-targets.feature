Feature: List targets sorted by number of dependencies

  Scenario: The project is the microfeature fixture
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    Then tuist generates the project at Frameworks/UIComponentsFramework
    Then run tuist migration list-targets for UIComponents in ios_workspace_with_microfeature_architecture matches list-targets-ui-components.json
    Then tuist generates the project at Frameworks/CoreFramework
    Then run tuist migration list-targets for Core in ios_workspace_with_microfeature_architecture matches list-targets-core.json
    Then tuist generates the project at Frameworks/DataFramework
    Then run tuist migration list-targets for Data in ios_workspace_with_microfeature_architecture matches list-targets-data.json
