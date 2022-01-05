# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    class FocusTest < TestCase
      def test_call
        # Given
        Utilities::System
          .expects(:tuist)
          .with("cache", "warm", "--dependencies-only")
        Utilities::System
          .expects(:tuist)
          .with("dependencies", "fetch")
        targets = ["TuistSupport", "TuistSupportTests"]
        Utilities::System
          .expects(:tuist)
          .with("focus", *targets)

        # Then
        Services::Focus.call(targets: targets)
      end
    end
  end
end
