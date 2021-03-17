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
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            gem_path = Gem.loaded_specs["rubocop"].full_gem_path
            executable_path = File.join(gem_path, "exe/rubocop")
            arguments = [executable_path]
            arguments << "-A" if fix
            Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
