Then(/tuist lints the project and fails/) do
  _, _, status = Open3.capture3("swift", "run", "tuist", "lint", "project" "--path", @dir)
  refute(status.success?, "Expected 'tuist lint project' to fail but it didn't")
end