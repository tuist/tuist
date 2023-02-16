# frozen_string_literal: true

require "test_helper"
require "octokit"

module Fourier
  module Utilities
    class RubocopLinterTest < TestCase
      def test_lint
        # Given
        from = "/"
        directories = ["/test"]
        fix = true
        gem_path = Gem.loaded_specs["rubocop"].full_gem_path
        executable_path = File.join(gem_path, "exe/rubocop")
        arguments = [executable_path]
        arguments << "-A" if fix
        arguments.push("-c", File.expand_path(".rubocop.yml", Constants::ROOT_DIRECTORY))
        arguments.concat(directories)

        Utilities::System.expects(:system).with(*arguments)

        # When/then
        RubocopLinter.lint(
          from: from,
          directories: directories,
          fix: true,
        )
      end
    end
  end
end
