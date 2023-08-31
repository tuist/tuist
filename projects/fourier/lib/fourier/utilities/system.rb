# frozen_string_literal: true

require "cli/kit"

module Fourier
  module Utilities
    module System
      class << self
        def system(*args)
          Kernel.system(*args) || exit(1)
        end

        def tuist(*args)
          Dir.chdir(Constants::TUIST_DIRECTORY) do
            self.system("swift", "build")
            @tuist = ".build/debug/tuist"
            self.system(@tuist, *args)
          end
        end

        def fixturegen(*args)
          Dir.chdir(Constants::ROOT_DIRECTORY) do
            self.system("swift", "run", "fixturegen", *args)
          end
        end
      end
    end
  end
end
