# frozen_string_literal: true
module Fourier
  module Services
    module Build
      class Bench < Base
        def call
          Dir.chdir(Constants::TUISTBENCH_DIRECTORY) do
            Utilities::System.system("swift", "build")
          end
        end
      end
    end
  end
end
