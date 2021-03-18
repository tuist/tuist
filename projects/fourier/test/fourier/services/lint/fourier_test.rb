# frozen_string_literal: true
require "test_helper"

module Fourier
  module Services
    module Lint
      class FourierTest < TestCase
        def test_calls_system_with_the_right_arguments
          # Given
          subject = Services::Lint::Fourier.new(fix: false)
          gem_path = Gem.loaded_specs["rubocop"].full_gem_path
          executable_path = File.join(gem_path, "exe/rubocop")
          Utilities::System
            .expects(:system)
            .with(executable_path)

          # When/Then
          subject.call
        end

        def test_calls_system_with_the_right_arguments_when_fix_is_true
          # Given
          subject = Services::Lint::Fourier.new(fix: true)
          gem_path = Gem.loaded_specs["rubocop"].full_gem_path
          executable_path = File.join(gem_path, "exe/rubocop")
          Utilities::System
            .expects(:system)
            .with(executable_path, "-A")

          # When/Then
          subject.call
        end
      end
    end
  end
end
