Feature: Focuses projects with pre-compiled cached xcframeworks

  Scenario: The project is an application with templates (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache with xcframeworks
    When tuist focuses the targets MyApp,MyAppTests using xcframeworks
    Then MyApp links the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppUI
    Then I should be able to build for iOS the scheme MyApp
    Then I should be able to test for iOS the scheme MyApp

Scenario: The project is an application (ios_workspace_with_microfeature_architecture)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    And tuist warms the cache with xcframeworks
    When tuist focuses the targets App,AppTests using xcframeworks
    Then App embeds the xcframework Core
    Then App embeds the xcframework Data
    Then App embeds the xcframework FeatureContracts
    Then App embeds the xcframework UIComponents
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App

Scenario: The project is an application and a target is modified after being cached (ios_workspace_with_microfeature_architecture)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    And tuist warms the cache with xcframeworks
    And I add an empty line at the end of the file Frameworks/FeatureAFramework/Sources/FrameworkA.swift
    When tuist focuses the targets App,AppTests using xcframeworks
    Then App embeds the xcframework Core
    Then App embeds the xcframework Data
    Then App embeds the framework FrameworkA
    Then App links the framework FrameworkA
    Then App doesn't embed the xcframework FrameworkA
    Then App embeds the xcframework UIComponents
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App

Scenario: The project is an application and a target is generated as sources (ios_workspace_with_microfeature_architecture)
    Given that tuist is available 
    And I have a working directory
    Then I copy the fixture ios_workspace_with_microfeature_architecture into the working directory
    And tuist warms the cache with xcframeworks
    When tuist focuses the targets App,AppTests,FrameworkA using xcframeworks
    Then App embeds the xcframework Core
    Then App embeds the xcframework Data
    Then App embeds the framework FrameworkA
    Then App links the framework FrameworkA
    Then App doesn't embed the xcframework FrameworkA
    Then App embeds the xcframework UIComponents
    Then I should be able to build for iOS the scheme App
    Then I should be able to test for iOS the scheme App
    
  Scenario: The project is an application with templates using device caches (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache with device xcframeworks
    When tuist focuses the targets MyApp using device xcframeworks
    Then MyApp links the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppUI
    Then I should be able to build for device of iOS the scheme MyApp
    
  Scenario: The project is an application with templates using simulator caches (ios_app_with_templates)
    Given that tuist is available 
    And I have a working directory
    And I initialize a ios application named MyApp
    And tuist warms the cache with simulator xcframeworks
    When tuist focuses the targets MyApp,MyAppTests using simulator xcframeworks
    Then MyApp links the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppKit
    Then MyApp embeds the xcframework MyAppUI
    Then I should be able to build for iOS the scheme MyApp
    Then I should be able to test for iOS the scheme MyApp