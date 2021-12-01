# frozen_string_literal: true

module Fourier
  module Services
    module Lint
      class Cloud < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          directories = [
            Constants::CLOUD_DIRECTORY,
          ]
          Utilities::RubocopLinter.lint(
            from: Constants::CLOUD_DIRECTORY,
            fix: fix,
            directories: directories
          )
        end
      end
    end
  end
end
