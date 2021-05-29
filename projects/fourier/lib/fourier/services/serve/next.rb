# frozen_string_literal: true
module Fourier
  module Services
    module Serve
      class Next < Base
        def call
          Dir.chdir(Constants::NEXT_DIRECTORY) do
            Utilities::System.system("yarn", "develop")
          end
        end
      end
    end
  end
end
