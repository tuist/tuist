# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class BackboneTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          directories = [
            Constants::BACKBONE_DIRECTORY,
          ]
          Utilities::RubocopLinter.expects(:lint)
            .with(
              from: Constants::BACKBONE_DIRECTORY,
              fix: true,
              directories: directories,
            )

          # When/Then
          Backbone.call(fix: true)
        end
      end
    end
  end
end
