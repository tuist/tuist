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
    end
  end
end
