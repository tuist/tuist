# frozen_string_literal: true

require "test_helper"

# frozen_string_literal: true
module Fourier
  module Services
    module Serve
      class DocsTest < TestCase
        def test_call
          # Given
          Utilities::System
            .expects(:system)
            .with("yarn", "start")

          # When/then
          Serve::Docs.call
        end
      end
    end
  end
end
