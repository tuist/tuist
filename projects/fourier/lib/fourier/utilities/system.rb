# frozen_string_literal: true
require "cli/kit"

module Fourier
  module Utilities
    module System
      def self.system(*args)
        Kernel.system(*args) || Kernel.abort
      end

      def self.tuist(*args)
        Dir.chdir(Constants::TUIST_DIRECTORY) do
          self.system("swift", "build")
          self.system("swift", "run", "tuist", *args)
        end
      end

      def self.fixturegen(*args)
        Dir.chdir(Constants::FIXTUREGEN_DIRECTORY) do
          self.system("swift", "build")
          self.system("swift", "run", "fixturegen", *args)
        end
      end
    end
  end
end
