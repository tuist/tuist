Then(/tuist lints project's code and passes/) do
  out, _, _ = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  actual_msg = out.strip
  expected_msg = "Done linting! Found 0 violations, 0 serious"

  error_message = <<~EOD
    The output message:
      #{actual_msg}

    Does not contain the expected:
      #{expected_msg}
  EOD
  
  assert actual_msg.include?(expected_msg), error_message
end

Then(/tuist lints project's code and fails/) do
  out, _, _ = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  actual_msg = out.strip
  dont_expected_msg = "Done linting! Found 0 violations, 0 serious"

  error_message = <<~EOD
    The output message:
      #{actual_msg}

    Does not contain the expected:
      #{dont_expected_msg}
  EOD
  
  assert !actual_msg.include?(dont_expected_msg), error_message
end

Then(/tuist lints code of target with name "(.+)" and passes/) do |targetName|
  out, _, _ = Open3.capture3("swift", "run", "tuist", "lint", "code", targetName, "--path", @dir)
  actual_msg = out.strip
  expected_msg = "Done linting! Found 0 violations, 0 serious"

  error_message = <<~EOD
    The output message:
      #{actual_msg}

    Does not contain the expected:
      #{expected_msg}
  EOD
  
  assert actual_msg.include?(expected_msg), error_message
end

Then(/tuist lints code of target with name "(.+)" and failes/) do |targetName|
  out, _, _ = Open3.capture3("swift", "run", "tuist", "lint", "code", targetName, "--path", @dir)
  actual_msg = out.strip
  dont_expected_msg = "Done linting! Found 0 violations, 0 serious"

  error_message = <<~EOD
    The output message:
      #{actual_msg}

    Does not contain the expected:
      #{dont_expected_msg}
  EOD
  
  assert !actual_msg.include?(dont_expected_msg), error_message
end