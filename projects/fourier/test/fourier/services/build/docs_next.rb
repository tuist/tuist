# frozen_string_literal: true

require "test_helper"

# frozen_string_literal: true
module Fourier
  module Services
    module Build
      class DocsTest < TestCase
        def test_call
          # Given
          Utilities::System
            .expects(:system)
            .with("yarn", "build")

          # When/then
          Build::Docs.call
        end
      end
    end
  end
end
