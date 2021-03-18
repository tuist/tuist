# frozen_string_literal: true
module Fourier
  module Services
    class Base
      def self.call(*args, &block)
        new(*args).call(&block)
      end

      def call
        raise NotImplementedError
      end

      def root_directory
        Fourier::Constants::ROOT_DIRECTORY
      end

      def fourier_directory
        File.join(Fourier::Constants::ROOT_DIRECTORY, "projects/fourier")
      end

      def tuist_directory
        File.join(Fourier::Constants::ROOT_DIRECTORY)
      end

      def vendor_path(path)
        File.join(Fourier::Constants::VENDOR_DIRECTORY, path)
      end
    end
  end
end
