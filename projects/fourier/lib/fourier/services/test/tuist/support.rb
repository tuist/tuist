# frozen_string_literal: true

module Fourier
  module Services
    module Test
      module Tuist
        class Support < Base
          attr_reader :source

          def initialize(source: false)
            @source = source
          end

          def call
            Utilities::System.tuist("test", "TuistSupport", source: @source)
          end
        end
      end
    end
  end
end
