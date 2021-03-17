# frozen_string_literal: true
module Fourier
  module Services
    module Format
      class Tuist < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            arguments = [vendor_path("swiftformat"), ".", "--quiet"]
            unless fix
              arguments << "--lint"
            end
            Fourier::Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
