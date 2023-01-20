# frozen_string_literal: true

module Fourier
  module Utilities
    module RubocopLinter
      class << self
        def lint(from:, directories:, fix: false)
          Dir.chdir(from) do
            gem_path = Gem.loaded_specs["rubocop"].full_gem_path
            executable_path = File.join(gem_path, "exe/rubocop")
            arguments = [executable_path]
            arguments << "-A" if fix
            arguments.push("-c", File.expand_path(".rubocop.yml", Constants::ROOT_DIRECTORY))
            arguments.concat(directories)
            Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
