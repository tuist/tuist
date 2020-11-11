Feature: Manipulate a project using Tuist with a helper plugin and be able to import it in all supported manifest types.

  Scenario: The project is an iOS application (app_with_helper_plugin)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_helper_plugin into the working directory
    Then tuist generates the project
    Then I should be able to build for iOS the scheme App

  Scenario: The project is an iOS application (app_with_helper_plugin)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_helper_plugin into the working directory
    Then tuist sets up the project
    Then I should have /tmp/my_test_tool installed
    
  Scenario: The project is an application with templates (app_with_helper_plugin)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_helper_plugin into the working directory
    Then tuist scaffolds a custom template to TemplateProject named TemplateProject
    Then content of a file named TemplateProject/custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named TemplateProject/generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: ios and name: TemplateProject

      """
