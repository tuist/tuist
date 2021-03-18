# frozen_string_literal: true
require "rake/testtask"

module Fourier
  module Services
    module Test
      class Fourier < Base
        def call
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            lib_directory = File.expand_path("lib", Constants::FOURIER_DIRECTORY)
            test_directory = File.expand_path("test", Constants::FOURIER_DIRECTORY)
            test_paths = Dir.glob(File.join(Constants::FOURIER_DIRECTORY, "test/**/*_test.rb"))
            arguments = [
              "ruby",
              "-I#{lib_directory}",
              "-I#{test_directory}",
              "-e \"ARGV.each {|f| require f}\"",
              *test_paths,
            ].join(" ")
            Utilities::System.system(arguments)
          end
        end
      end
    end
  end
end
