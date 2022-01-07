# frozen_string_literal: true

module Fourier
  module Services
    class Focus < Base
      attr_reader :targets

      def initialize(targets:)
        @targets = targets
      end

      def call
        fetch = ["fetch"]
        Utilities::System.tuist(*fetch)

        cache_warm = ["cache", "warm", "--dependencies-only"]
        Utilities::System.tuist(*cache_warm)

        focus = ["focus"] + targets
        Utilities::System.tuist(*focus)
      end
    end
  end
end
