# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class FourierTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          directories = [
            Constants::FOURIER_DIRECTORY,
          ]
          Utilities::RubocopLinter.expects(:lint)
            .with(
              from: Constants::FOURIER_DIRECTORY,
              fix: true,
              directories: directories,
            )

          # When/Then
          Fourier.call(fix: true)
        end
      end
    end
  end
end
