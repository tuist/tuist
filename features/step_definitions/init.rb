When(/I initialize a (.+) (.+) named (.+)/) do |platform, product, name|
  Tuist::System.run("swift", "run", "tuist", "init", "--path", @dir, "--platform", platform, "--product", product, "--name", name)
  @workspace_path = File.join(@dir, "#{name}.xcworkspace")
end
