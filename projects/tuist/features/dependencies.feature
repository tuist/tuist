Feature: Tuist dependencies.

    Scenario: The project is an application with Carthage Dependencies.swift (app_with_carthage_dependencies)
        Given that tuist is available
        And I have a working directory
        Then I copy the fixture app_with_carthage_dependencies into the working directory
        Then tuist fetches dependencies
        Then tuist generates the project 
        Then tuist builds the scheme App from the project

    Scenario: The project is an application with SPM Dependencies.swift (app_with_spm_dependencies)
        Given that tuist is available
        And I have a working directory
        Then I copy the fixture app_with_spm_dependencies into the working directory
        Then tuist fetches dependencies
        Then tuist generates the project
        Then tuist builds the scheme App from the project

    Scenario: The project is a sub project within a workspace with SPM Dependencies.swift (app_with_spm_dependencies)
        Given that tuist is available
        And I have a working directory
        Then I copy the fixture app_with_spm_dependencies into the working directory
        Then tuist fetches dependencies
        Then tuist generates the project at /Features/FeatureOne
        Then tuist builds the scheme FeatureOneFramework_iOS from the project at Features/FeatureOne  
