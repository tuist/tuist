# frozen_string_literal: true
module Fourier
  module Services
    module Build
      class Next < Base
        def call
          Dir.chdir(Constants::NEXT_DIRECTORY) do
            Utilities::System.system("yarn", "build")
          end
        end
      end
    end
  end
end
