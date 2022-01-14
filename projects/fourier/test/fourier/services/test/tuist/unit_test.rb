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
              .with("dependencies", "fetch", source: false)
            Utilities::System
              .expects(:tuist)
              .with("test", source: false)
            Utilities::System
              .expects(:system)
              .with("swift", "test")

            # When/Then
            Unit.call(source: false)
          end
        end
      end
    end
  end
end
