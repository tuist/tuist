# frozen_string_literal: true

module Fourier
  module Services
    module Generate
      class Tuist < Base
        attr_reader :open, :source

        def initialize(open: false, source: false)
          @open = open
          @source = source
        end

        def call
          dependencies = ["dependencies", "fetch"]
          Utilities::System.tuist(*dependencies, source: @source)

          generate = ["generate"]
          generate << "--open" if open
          Utilities::System.tuist(*generate, source: @source)
        end
      end
    end
  end
end
