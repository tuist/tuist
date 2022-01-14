# frozen_string_literal: true

module Fourier
  module Services
    module Build
      module Tuist
        class All < Base
          attr_reader :source

          def initialize(source: false)
            @source = source
          end

          def call
            dependencies = ["dependencies", "fetch"]
            Utilities::System.tuist(*dependencies, source: @source)
            Utilities::System.tuist("build", "--generate", source: @source)
          end
        end
      end
    end
  end
end
