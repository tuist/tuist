Then(/^tuist tests the project$/) do
    system("swift", "run", "tuist", "test", "--path", @dir)
  end
  Then(/^tuist tests the scheme ([a-zA-Z\-]+) from the project$/) do |scheme|
    system("swift", "run", "tuist", "test", scheme, "--path", @dir)
  end
  
  Then(/^tuist tests the scheme ([a-zA-Z\-]+) and configuration ([a-zA-Z]+) from the project$/) do |scheme, configuration|
    system("swift", "run", "tuist", "test", scheme, "--path", @dir, "--configuration", configuration)
  end
  
  Then(/^tuist tests the project at (.+)$/) do |path|
    system("swift", "run", "tuist", "test", "--path", File.join(@dir, path))
  end
  