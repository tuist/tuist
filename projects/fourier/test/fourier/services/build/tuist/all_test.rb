# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Build
      module Tuist
        class AllTest < TestCase
          def test_call
            # Given
            Utilities::System
              .expects(:tuist)
              .with("fetch")
            Utilities::System
              .expects(:tuist)
              .with("build", "--generate")

            # Then
            Services::Build::Tuist::All.call
          end
        end
      end
    end
  end
end
