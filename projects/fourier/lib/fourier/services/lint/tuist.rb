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
          directories = [
            File.expand_path("Sources", Constants::ROOT_DIRECTORY),
          ]
          Utilities::SwiftLinter.lint(
            directories: directories,
            fix: fix
          )
        end
      end
    end
  end
end
