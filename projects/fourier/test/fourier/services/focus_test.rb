# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    class FocusTest < TestCase
      def test_call
        # Given
        Utilities::System
          .expects(:tuist)
          .with("cache", "warm", "--dependencies-only", source: false)
        Utilities::System
          .expects(:tuist)
          .with("dependencies", "fetch", source: false)
        targets = ["TuistSupport", "TuistSupportTests"]
        Utilities::System
          .expects(:tuist)
          .with("focus", *targets, source: false)

        # Then
        Services::Focus.call(targets: targets, source: false)
      end
    end
  end
end
