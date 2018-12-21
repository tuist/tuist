# Changelog
if !git.modified_files.include?("CHANGELOG.md") && !declared_trivial
  message = <<~MESSAGE
    Please include a CHANGELOG entry.
    You can find it at [CHANGELOG.md](https://github.com/tuist/tuist/blob/master/CHANGELOG.md).
  MESSAGE
  fail(message, sticky: false)
end

# Swiftlint
swiftlint.lint_files