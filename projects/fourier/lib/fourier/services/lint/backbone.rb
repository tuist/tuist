# frozen_string_literal: true

module Fourier
  module Services
    module Lint
      class Backbone < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          directories = [
            Constants::BACKBONE_DIRECTORY,
          ]
          Utilities::RubocopLinter.lint(
            from: Constants::BACKBONE_DIRECTORY,
            fix: fix,
            directories: directories
          )
        end
      end
    end
  end
end
