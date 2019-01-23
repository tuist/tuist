Feature: Generate a new project using Tuist




  Scenario: The project is a directory (sample_3) without valid manifest file
    Given that tuist is available
    And I have a working directory
    Then I copy the fixture sample_3 into the working directory
    Then tuist generates reports error "❌ Error: Couldn't find manifest at path:"
