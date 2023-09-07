# frozen_string_literal: true

module Fourier
  module Services
    module Build
      class Benchmark < Base
        attr_reader :configuration
        def initialize(configuration: "debug")
          @configuration = configuration
        end

        def call
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            Utilities::System.system("swift", "build", "--configuration", configuration, "--target", "tuistbenchmark")
          end
        end
      end
    end
  end
end
