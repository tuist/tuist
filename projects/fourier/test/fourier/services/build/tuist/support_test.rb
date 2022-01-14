# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Build
      module Tuist
        class SupportTest < TestCase
          def test_call
            # Given
            Utilities::System
              .expects(:tuist)
              .with("build", "TuistSupport", source: false)

            # Then
            Services::Build::Tuist::Support.call(source: false)
          end
        end
      end
    end
  end
end
