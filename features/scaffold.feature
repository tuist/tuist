Feature: Scaffold a project using Tuist

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_templates into the working directory
    Then tuist scaffolds a custom template to TemplateProject named TemplateProject
    Then content of a file named TemplateProject/custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named TemplateProject/generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: ios and name: TemplateProject

      """
    # Uses new naming where name of template file is no longer `Template.swift` but `name_of_template.swift`
    Then tuist scaffolds a custom_two template to TemplateProject named TemplateProject
    Then content of a file named TemplateProject/custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named TemplateProject/generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: ios and name: TemplateProject

      """
  Scenario: The project is a just initialized project
    Given that tuist is available
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist scaffolds a framework template to Projects/ named MyFeature
    When tuist generates the project at Projects/MyFeature
    Then I should be able to build for iOS the scheme MyFeature
    Then I should be able to test for iOS the scheme MyFeature
