# frozen_string_literal: true

module Fourier
  module Services
    module Serve
      class Docs < Base
        def call
          Dir.chdir(Constants::DOCS_DIRECTORY) do
            Utilities::System.system("yarn", "start")
          end
        end
      end
    end
  end
end
