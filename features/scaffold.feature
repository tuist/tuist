Feature: Scaffold a project using Tuist

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_app_with_templates into the working directory
    Then tuist scaffolds a custom template to TemplateProject named TemplateProject and platform ios
    Then content of a file named custom_dir/custom.swift in a directory TemplateProject should be equal to "// this is test TemplateProject content"
