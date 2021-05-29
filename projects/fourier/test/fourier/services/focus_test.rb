# frozen_string_literal: true
require "test_helper"

module Fourier
  module Services
    class FocusTest < TestCase
      def test_call
        # Given
        target = "TuistSupport"
        Utilities::System
          .expects(:tuist)
          .with("focus", target)

        # Then
        Services::Focus.call(target: target)
      end
    end
  end
end
