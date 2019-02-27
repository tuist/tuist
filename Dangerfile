# frozen_string_literal: true
require 'danger-swiftformat'

all_files = git.modified_files + git.added_files

# Changelog
unless git.modified_files.include?("CHANGELOG.md")
  message = <<~MESSAGE
    Please include a CHANGELOG entry.
    You can find it at [CHANGELOG.md](https://github.com/tuist/tuist/blob/master/CHANGELOG.md).
  MESSAGE
  warn(message)
end

# Swiftformat
swiftformat.check_format(fail_on_error: true)

# Update documentation
if all_files.any? { |f| f =~ %r{Sources/} }
  message = <<~MESSAGE
    Have you introduced any user-facing changes? If so, please take some time to [update the documentation](https://github.com/tuist/tuist/blob/master/docs). Keeping the documentation up to date makes it easier for users to learn how to use Tuist.
  MESSAGE
  warn(message)
end

# Rubocop
rubocop.lint
