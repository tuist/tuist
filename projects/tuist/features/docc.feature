Feature: Tuist docc

    Scenario: The project is an application with docc documentation (app_with_docc)
        Given that tuist is available
        And I have a working directory
        Then I copy the fixture app_with_docc into the working directory
        Then tuist generates the project 
        Then xcodebuild compiles the docc archive
        Then a directory build/Release-iphoneos/SlothCreator.doccarchive exists
