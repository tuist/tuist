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
    Then tuist scaffolds a custom_using_filters template to TemplateProject named TemplateProject
    Then content of a file named TemplateProject/custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named TemplateProject/generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: iOS and snake case name: template_project

      """

  Scenario: The project is an application with templates from plugins (app_with_plugins)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_plugins into the working directory
    # Local template plugin
    Then tuist scaffolds a custom template to PluginTemplate named PluginTemplate
    Then content of a file named PluginTemplate/custom.swift in a directory PluginTemplate should be equal to // this is test PluginTemplate content
    Then content of a file named PluginTemplate/generated.swift in a directory PluginTemplate should be equal to:
      """
      // Generated file with platform: ios and name: PluginTemplate

      """
    # Remote template plugin
    Then tuist scaffolds a custom_two template to PluginTemplate named PluginTemplate
    Then content of a file named PluginTemplate/custom.swift in a directory PluginTemplate should be equal to // this is test PluginTemplate content
    Then content of a file named PluginTemplate/generated.swift in a directory PluginTemplate should be equal to:
      """
      // Generated file with platform: ios and name: PluginTemplate

      """
