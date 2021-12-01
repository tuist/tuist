# frozen_string_literal: true

module Fourier
  module Services
    module Lint
      class Fourier < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          directories = [
            Constants::FOURIER_DIRECTORY,
          ]
          Utilities::RubocopLinter.lint(
            from: Constants::FOURIER_DIRECTORY,
            fix: fix,
            directories: directories
          )
        end
      end
    end
  end
end
