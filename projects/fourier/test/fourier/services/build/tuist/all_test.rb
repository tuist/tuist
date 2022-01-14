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
              .with("dependencies", "fetch", source: false)
            Utilities::System
              .expects(:tuist)
              .with("build", "--generate", source: false)

            # Then
            Services::Build::Tuist::All.call(source: false)
          end
        end
      end
    end
  end
end
