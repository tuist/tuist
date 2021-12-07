# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Format
      class SwiftTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          subject = Services::Format::Swift.new(fix: false)
          Utilities::System
            .expects(:system)
            .with(subject.vendor_path("swiftformat/swiftformat"), ".", "--lint")

          # When/Then
          subject.call
        end

        def test_calls_system_with_the_right_arguments_when_fix_is_true
          # Given
          subject = Services::Format::Swift.new(fix: true)
          Utilities::System
            .expects(:system)
            .with(subject.vendor_path("swiftformat/swiftformat"), ".")

          # When/Then
          subject.call
        end
      end
    end
  end
end
