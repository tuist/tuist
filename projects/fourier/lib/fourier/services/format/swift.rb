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
            arguments = [vendor_path("swiftformat/swiftformat"), ".", "--swiftversion", "5.5.1"]
            unless fix

            end
            Fourier::Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
