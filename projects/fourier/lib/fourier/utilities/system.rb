# frozen_string_literal: true
module Fourier
  module Utilities
    module System
      def self.system(*args)
        Kernel.system(*args) || Kernel.abort
      end

      def self.tuist(*args)
        Dir.chdir(Constants::ROOT_DIRECTORY) do
          self.system("swift", "build")
          self.system("swift", "run", "tuist", *args)
        end
      end
    end
  end
end
