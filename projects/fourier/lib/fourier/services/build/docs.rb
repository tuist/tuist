# frozen_string_literal: true

module Fourier
  module Services
    module Build
      class Docs < Base
        def call
          Dir.chdir(Constants::DOCS_DIRECTORY) do
            Utilities::System.system("yarn", "build")
          end
        end
      end
    end
  end
end
