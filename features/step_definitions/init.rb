When(/I initialize a (.+) (.+) named (.+)/) do |platform, product, name|
  Tuist::System.run("swift", "run", "tuist", "init", "--path", @dir, "--platform", platform, "--product", product, "--name", name)
end
