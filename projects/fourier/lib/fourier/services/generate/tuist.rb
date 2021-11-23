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
          fetch = ["fetch"]
          Utilities::System.tuist(*fetch)

          generate = ["generate"]
          generate << "--open" if open
          Utilities::System.tuist(*generate)
        end
      end
    end
  end
end
