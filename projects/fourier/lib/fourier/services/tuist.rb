# frozen_string_literal: true
module Fourier
  module Services
    class Tuist < Base
      attr_reader :arguments

      def initialize(*arguments)
        @arguments = arguments
      end

      def call
        Utilities::System.tuist(*arguments)
      end
    end
  end
end
