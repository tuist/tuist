# frozen_string_literal: true
require "test_helper"

module Fourier
  module Services
    module Generate
      class TuistTest < TestCase
        def test_calls_tuist_with_the_right_arguments
          # Given
          Utilities::System.expects(:tuist).with("generate")

          # When/Then
          Fourier::Services::Generate::Tuist.call(open: false)
        end

        def test_calls_tuist_with_the_right_arguments_when_open_is_true
           # Given
           Utilities::System.expects(:tuist).with("generate", "--open")

           # When/Then
           Fourier::Services::Generate::Tuist.call(open: true)
        end
      end
    end
  end
end
