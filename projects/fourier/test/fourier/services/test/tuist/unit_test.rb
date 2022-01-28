# frozen_string_literal: true

require "test_helper"

# frozen_string_literal: true

module Fourier
  module Services
    module Test
      module Tuist
        class UnitTest < TestCase
          def test_call
            # Given
            Utilities::System
              .expects(:tuist)
              .with("fetch")
            Utilities::System
              .expects(:tuist)
              .with("test")

            # When/Then
            Unit.call
          end
        end
      end
    end
  end
end
