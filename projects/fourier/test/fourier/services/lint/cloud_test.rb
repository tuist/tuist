# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class CloudTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          directories = [
            Constants::CLOUD_DIRECTORY,
          ]
          Utilities::RubocopLinter.expects(:lint)
            .with(
              from: Constants::CLOUD_DIRECTORY,
              fix: true,
              directories: directories,
            )

          # When/Then
          Cloud.call(fix: true)
        end
      end
    end
  end
end
