# frozen_string_literal: true
require "test_helper"

module Fourier
  module Services
    module Lint
      class TuistTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          subject = Services::Lint::Tuist.new(fix: false)
          Utilities::System
            .expects(:system)
            .with(subject.vendor_path("swiftlint"), "--quiet")

          # When/Then
          subject.call
        end

        def test_calls_system_with_the_right_arguments_when_fix_is_true
          # Given
          subject = Services::Lint::Tuist.new(fix: true)
          Utilities::System
            .expects(:system)
            .with(subject.vendor_path("swiftlint"), "--quiet", "autocorrect")

          # When/Then
          subject.call
        end
      end
    end
  end
end
