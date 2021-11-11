# frozen_string_literal: true

module Fourier
  module Services
    module Generate
      class Tuist < Base
        attr_reader :open

        def initialize(open: false)
          @open = open
        end

        def call
          dependencies = ["dependencies", "fetch"]
          Utilities::System.tuist(*dependencies)

          cache_warm = ["cache", "warm", "--dependencies-only"]
          Utilities::System.tuist(*cache_warm)

          focus = ["focus"]
          focus << "--no-open" if !open
          Utilities::System.tuist(*focus)
        end
      end
    end
  end
end
