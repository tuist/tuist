# frozen_string_literal: true

module Fourier
  module Services
    module Generate
      class Tuist < Base
        attr_reader :open
        attr_reader :targets

        def initialize(open: false, targets: "")
          @open = open
          @targets = targets
        end

        def call
          dependencies = ["dependencies", "fetch"]
          Utilities::System.tuist(*dependencies)

          cache_warm = ["cache", "warm", "--dependencies-only"]
          cache_warm << targets
          Utilities::System.tuist(*cache_warm)

          generate = ["generate"]
          generate << "--open" if open
          generate << targets
          Utilities::System.tuist(*generate)
        end
      end
    end
  end
end
