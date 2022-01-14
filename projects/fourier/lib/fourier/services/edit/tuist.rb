# frozen_string_literal: true

module Fourier
  module Services
    module Edit
      class Tuist < Base
        attr_reader :source

        def initialize(source: false)
          @source = source
        end

        def call
          Utilities::System.tuist("edit", "--only-current-directory", source: @source)
        end
      end
    end
  end
end
