# frozen_string_literal: true
module Fourier
  module Services
    module Lint
      class Tuist < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            arguments = [vendor_path("swiftlint"), "--quiet"]
            arguments << "autocorrect" if fix
            Fourier::Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
