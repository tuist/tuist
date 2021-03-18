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
          arguments = ["generate"]
          arguments << "--open" if open
          Utilities::System.tuist(*arguments)
        end
      end
    end
  end
end
