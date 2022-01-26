module JWT
  module Algos
    module Unsupported
      module_function

      SUPPORTED = [].freeze

      def sign(*)
        raise NotImplementedError, 'Unsupported signing method'
      end

      def verify(*)
        raise JWT::VerificationError, 'Algorithm not supported'
      end
    end
  end
end
