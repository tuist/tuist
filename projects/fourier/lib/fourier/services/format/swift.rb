# frozen_string_literal: true

module Fourier
  module Services
    module Format
      class Swift < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            arguments = [vendor_path("swift-format"), "."]
            if fix
              arguments << "--in-place"
            else
              arguments << "lint"
              arguments << "--strict"
            end
            arguments += ["--recursive", "--ignore-unparsable-files", "--configuration", ".swift-format.config.json"]
            Fourier::Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
