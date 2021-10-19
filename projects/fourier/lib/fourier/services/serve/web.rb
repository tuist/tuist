# frozen_string_literal: true

module Fourier
  module Services
    module Serve
      class Web < Base
        def call
          Dir.chdir(Constants::WEBSITE_DIRECTORY) do
            Utilities::System.system("yarn", "develop")
          end
        end
      end
    end
  end
end
