# frozen_string_literal: true

module Fourier
  module Services
    module Test
      module Tuist
        class Unit < Base
          def call
            fetch = ["fetch"]
            Utilities::System.tuist(*fetch)
            Utilities::System.tuist("test")
            Dir.chdir(Constants::TUIST_DIRECTORY) do
              Utilities::System.system("swift", "test")
            end
          end
        end
      end
    end
  end
end
