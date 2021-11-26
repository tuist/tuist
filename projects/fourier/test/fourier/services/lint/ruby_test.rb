# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module Lint
      class RubyTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          subject = Services::Lint::Ruby.new(fix: false)
          gem_path = Gem.loaded_specs["rubocop"].full_gem_path
          executable_path = File.join(gem_path, "exe/rubocop")
          Utilities::System
            .expects(:system)
            .with(executable_path, "-c", File.expand_path(".rubocop.yml", Constants::ROOT_DIRECTORY))

          # When/Then
          subject.call
        end

        def test_calls_system_with_the_right_arguments_when_fix_is_true
          # Given
          subject = Services::Lint::Ruby.new(fix: true)
          gem_path = Gem.loaded_specs["rubocop"].full_gem_path
          executable_path = File.join(gem_path, "exe/rubocop")
          Utilities::System
            .expects(:system)
            .with(executable_path, "-A", "-c", File.expand_path(".rubocop.yml", Constants::ROOT_DIRECTORY))

          # When/Then
          subject.call
        end
      end
    end
  end
end
