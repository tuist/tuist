Feature: Install dependencies Tuist.

    Scenario: The project is an application with framework and tests and Dependencies.swift (app_with_framework_and_tests_and_dependencies)
        Given that tuist is available
        And I have a working directory
        Then I copy the fixture app_with_framework_and_tests_and_dependencies into the working directory
        Then tuist fetches dependencies
        Then a directory Tuist/Dependencies/Carthage/Alamofire.xcframework exists
        Then a file Tuist/Dependencies/Carthage/.Alamofire.version exists
        Then a file Tuist/Dependencies/Lockfiles/Cartfile.resolved exists

