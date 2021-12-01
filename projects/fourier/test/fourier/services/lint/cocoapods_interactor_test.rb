# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class CocoapodsInteractorTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          directories = [
            Constants::COCOAPODS_INTERACTOR_DIRECTORY,
          ]
          Utilities::RubocopLinter.expects(:lint)
            .with(
              from: Constants::COCOAPODS_INTERACTOR_DIRECTORY,
              fix: true,
              directories: directories,
            )

          # When/Then
          CocoapodsInteractor.call(fix: true)
        end
      end
    end
  end
end
