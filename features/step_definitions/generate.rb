Then(/I generate the project/) do
  Tuist::System.run("swift", "run", "tuist", "generate", "--path", @dir)
end
