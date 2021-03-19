# frozen_string_literal: true
module Fourier
  module Services
    module Build
      class Web < Base
        def call
          Dir.chdir(Constants::WEBSITE_DIRECTORY) do
            Utilities::System.system("yarn", "build")
          end
        end
      end
    end
  end
end
