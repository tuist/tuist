# frozen_string_literal: true

module Fourier
  module Services
    module Lint
      class CocoapodsInteractor < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          directories = [
            Constants::COCOAPODS_INTERACTOR_DIRECTORY,
          ]
          Utilities::RubocopLinter.lint(
            from: Constants::COCOAPODS_INTERACTOR_DIRECTORY,
            fix: fix,
            directories: directories
          )
        end
      end
    end
  end
end
