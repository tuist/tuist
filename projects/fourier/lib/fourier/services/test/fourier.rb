# frozen_string_literal: true
require "rake/testtask"

module Fourier
  module Services
    module Test
      class Fourier < Base
        def call
          Dir.chdir(root_directory) do
            lib_directory = File.expand_path("lib", fourier_directory)
            test_directory = File.expand_path("test", fourier_directory)
            arguments = [
              "ruby",
              "-I#{lib_directory}",
              "-I#{test_directory}",
              *Dir.glob(File.join(fourier_directory, "test/**/*_test.rb")),
            ]

            Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
