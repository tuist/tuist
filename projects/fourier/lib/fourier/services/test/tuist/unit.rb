# frozen_string_literal: true

module Fourier
  module Services
    module Test
      module Tuist
        class Unit < Base
          attr_reader :source

          def initialize(source: false)
            @source = source
          end

          def call
            dependencies = ["dependencies", "fetch"]
            Utilities::System.tuist(*dependencies, source: @source)
            Utilities::System.tuist("test", source: @source)
            Dir.chdir(Constants::TUIST_DIRECTORY) do
              Utilities::System.system("swift", "test")
            end
          end
        end
      end
    end
  end
end
