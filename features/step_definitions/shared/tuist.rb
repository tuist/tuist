Given(/tuist is available/) do
  Tuist::System.run("swift", "build")
end
