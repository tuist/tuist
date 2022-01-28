Feature: Scaffold a project using Tuist

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_templates into the working directory
    Then tuist does fetch
    Then tuist scaffolds a custom template named TemplateProject
    Then content of a file named custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: ios and name: TemplateProject

      """
    Then tuist scaffolds a custom_using_filters template named TemplateProject
    Then content of a file named custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: iOS and snake case name: template_project

      """
    Then tuist scaffolds a custom_using_copy_folder template named TemplateProject
    Then content of a file named custom.swift in a directory TemplateProject should be equal to // this is test TemplateProject content
    Then content of a file named generated.swift in a directory TemplateProject should be equal to:
      """
      // Generated file with platform: ios and name: TemplateProject

      """
    Then content of a file named file1.txt in a directory TemplateProject/sourceFolder should be equal to:
      """
      Content of file 1

      """
    Then content of a file named file2.txt in a directory TemplateProject/sourceFolder/subFolder should be equal to:
      """
      Content of file 2

      """

  Scenario: The project is an application with templates from plugins (app_with_plugins)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_plugins into the working directory
    Then tuist does fetch
    # Local template plugin
    Then tuist scaffolds a custom template named PluginTemplate
    Then content of a file named custom.swift in a directory PluginTemplate should be equal to // this is test PluginTemplate content
    Then content of a file named generated.swift in a directory PluginTemplate should be equal to:
      """
      // Generated file with platform: ios and name: PluginTemplate

      """
    # Remote template plugin
    Then tuist scaffolds a custom_two template named PluginTemplate
    Then content of a file named custom.swift in a directory PluginTemplate should be equal to // this is test PluginTemplate content
    Then content of a file named generated.swift in a directory PluginTemplate should be equal to:
      """
      // Generated file with platform: ios and name: PluginTemplate

      """
