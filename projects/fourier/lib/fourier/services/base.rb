# frozen_string_literal: true

module Fourier
  module Services
    class Base
      class << self
        def call(*args, **kwargs, &block)
          new(*args, **kwargs).call(&block)
        end
      end

      def call
        raise NotImplementedError
      end

      def vendor_path(path)
        File.join(Fourier::Constants::VENDOR_DIRECTORY, path)
      end
    end
  end
end
