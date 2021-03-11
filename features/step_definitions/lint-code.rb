Then(/tuist lints project's code and passes/) do
  out, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  flunk(err) unless status.success?
end

Then(/tuist lints project's code and fails/) do
  out, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  flunk(err) if status.success?
end

Then(/tuist lints code of target with name "(.+)" and passes/) do |targetName|
  out, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", targetName, "--path", @dir)
  flunk(err) unless status.success?
end

Then(/tuist strict lints code of target with name "(.+)" and fails/) do |targetName|
  out, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", targetName, "--path", @dir, "--strict")
  flunk(err) if status.success?
end

Then(/tuist lints code of target with name "(.+)" and fails/) do |targetName|
  out, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", targetName, "--path", @dir)
  flunk(err) if status.success?
end
