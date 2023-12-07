Feature: Edit an existing project using Tuist

  Scenario: The project is an application with helpers, sub projects, Config.swift, Dependencies.swift and Project.swift (ios_app_with_helpers)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture ios_app_with_helpers into the working directory
    Then tuist edits the project
    Then I should be able to build for macOS the scheme Manifests

  Scenario: The project is a plugin with helpers (plugin).
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture plugin into the working directory
    Then tuist edits the project
    Then I should be able to build for macOS the scheme Plugins

  Scenario: The project is a project with plugins (app_with_plugins)
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture app_with_plugins into the working directory
    Then tuist does fetch
    Then tuist edits the project
    Then I should be able to build for macOS the scheme Manifests
    Then I should be able to build for macOS the scheme Plugins
    Then I should be able to build for macOS the scheme LocalPlugin
