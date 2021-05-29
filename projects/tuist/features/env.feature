Feature: The Tuist environment
    Scenario: Installing tuist from source
        Given that tuist is available
        Then tuistenv should succeed in installing the latest version