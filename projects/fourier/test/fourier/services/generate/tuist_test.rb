# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Generate
      class TuistTest < TestCase
        def test_calls_tuist_with_the_right_arguments
          # Given
          Utilities::System.expects(:tuist).with("dependencies", "fetch", source: false)
          Utilities::System.expects(:tuist).with("generate", source: false)

          # When/Then
          Fourier::Services::Generate::Tuist.call(open: false, source: false)
        end

        def test_calls_tuist_with_the_right_arguments_when_open_is_true
          # Given
          Utilities::System.expects(:tuist).with("dependencies", "fetch", source: false)
          Utilities::System.expects(:tuist).with("generate", "--open", source: false)

          # When/Then
          Fourier::Services::Generate::Tuist.call(open: true, source: false)
        end
      end
    end
  end
end
