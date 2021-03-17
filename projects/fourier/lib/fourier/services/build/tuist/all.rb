# frozen_string_literal: true
module Fourier
  module Services
    module Build
      module Tuist
        class All < Base
          def call
            Dir.chdir(tuist_directory) do
              Utilities::System.tuist("build")
            end
          end
        end
      end
    end
  end
end
