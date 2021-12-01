# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class FixturegenTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          directories = [
            File.expand_path("Sources", Constants::FIXTUREGEN_DIRECTORY),
          ]
          Utilities::SwiftLinter.expects(:lint)
            .with(directories: directories, fix: true)

          # When/Then
          Fixturegen.call(fix: true)
        end
      end
    end
  end
end
