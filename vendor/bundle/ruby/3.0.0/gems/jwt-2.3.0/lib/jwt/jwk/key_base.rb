# frozen_string_literal: true

module JWT
  module JWK
    class KeyBase
      attr_reader :keypair, :kid

      def initialize(keypair, kid = nil)
        @keypair = keypair
        @kid     = kid
      end

      def self.inherited(klass)
        ::JWT::JWK.classes << klass
      end
    end
  end
end
