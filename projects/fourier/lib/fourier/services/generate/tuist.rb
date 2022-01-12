# frozen_string_literal: true

module Fourier
  module Services
    module Generate
      class Tuist < Base
        attr_reader :no_open
        attr_reader :targets

        def initialize(no_open: false, targets: [])
          @no_open = no_open
          @targets = targets
        end

        def call
          fetch = ["fetch"]
          Utilities::System.tuist(*fetch)

          cache_warm = ["cache", "warm", "--dependencies-only"] + targets
          Utilities::System.tuist(*cache_warm)

          generate = ["generate"] + targets
          generate << "--no-open" if no_open
          Utilities::System.tuist(*generate)
        end
      end
    end
  end
end
