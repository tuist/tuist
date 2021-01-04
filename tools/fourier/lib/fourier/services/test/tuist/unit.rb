# frozen_string_literal: true
module Fourier
  module Services
    module Test
      module Tuist
        class Unit < Base
          def call
            Utilities::System.system(
              "swift", "test",
              "--package-path", Constants::ROOT_DIRECTORY
            )
          end
        end
      end
    end
  end
end
