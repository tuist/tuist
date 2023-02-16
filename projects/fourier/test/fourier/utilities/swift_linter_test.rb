# frozen_string_literal: true

require "test_helper"
require "octokit"

module Fourier
  module Utilities
    class SwiftLinterTest < TestCase
      def test_lint
        # Given
        directories = ["/test"]
        fix = true
        arguments = [
          File.join(Fourier::Constants::VENDOR_DIRECTORY, "swiftlint", "swiftlint"),
        ]
        if fix
          arguments << "--fix" if fix
        else
          arguments << "lint"
        end
        arguments << "--quiet"
        arguments.push("--config", Constants::SWIFTLINT_CONFIG_PATH)
        arguments.concat(directories.flat_map { |p| ["--path", p] })

        Utilities::System.expects(:system).with(*arguments)

        # When/then
        SwiftLinter.lint(
          directories: directories,
          fix: true,
        )
      end
    end
  end
end
