module JWT
  module Algos
    module None
      module_function

      SUPPORTED = %w[none].freeze

      def sign(*); end

      def verify(*)
        true
      end
    end
  end
end
