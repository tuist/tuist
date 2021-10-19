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
              .with("build", "TuistSupport")

            # Then
            Services::Build::Tuist::Support.call
          end
        end
      end
    end
  end
end
