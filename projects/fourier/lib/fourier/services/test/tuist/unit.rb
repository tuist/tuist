# frozen_string_literal: true
module Fourier
  module Services
    module Test
      module Tuist
        class Unit < Base
          def call
            Dir.chdir(tuist_directory) do
              Utilities::System.tuist("test")
            end
          end
        end
      end
    end
  end
end
