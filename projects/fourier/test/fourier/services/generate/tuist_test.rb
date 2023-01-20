# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Generate
      class TuistTest < TestCase
        def test_calls_tuist_with_the_right_arguments
          # Given
          Utilities::System.expects(:tuist).with("fetch")
          Utilities::System.expects(:tuist).with(
            "cache",
            "warm",
            "--dependencies-only",
            "--xcframeworks",
            "Target1",
            "Target2")
          Utilities::System.expects(:tuist).with("generate", "--xcframeworks", "Target1", "Target2")

          # When/Then
          Fourier::Services::Generate::Tuist.call(no_open: false, targets: ["Target1", "Target2"])
        end


        def test_calls_tuist_with_the_right_arguments_when_no_open_is_true
          # Given
          Utilities::System.expects(:tuist).with("fetch")
          Utilities::System.expects(:tuist).with(
            "cache",
            "warm",
            "--dependencies-only",
            "--xcframeworks",
            "Target1",
            "Target2")
          Utilities::System.expects(:tuist).with("generate", "--xcframeworks", "Target1", "Target2", "--no-open")

          # When/Then
          Fourier::Services::Generate::Tuist.call(no_open: true, targets: ["Target1", "Target2"])
        end
      end
    end
  end
end
