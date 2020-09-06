Feature: Lint code using Tuist (SwiftLint)

    Scenario: The project is an iOS application where one of the targets dont pass linting (app_with_framework_where_framework_failing_swiftlint) 
      Given that tuist is available
      And I have a working directory
      Then I copy the fixture app_with_framework_where_framework_failing_swiftlint into the working directory
      Then tuist lints project's code and fails
      Then tuist lints code of target with name "Framework" and fails
      Then tuist lints code of target with name "App" and passes