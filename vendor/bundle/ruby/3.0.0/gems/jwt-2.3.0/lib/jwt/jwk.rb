# frozen_string_literal: true

require_relative 'jwk/key_finder'

module JWT
  module JWK
    class << self
      def import(jwk_data)
        jwk_kty = jwk_data[:kty] || jwk_data['kty']
        raise JWT::JWKError, 'Key type (kty) not provided' unless jwk_kty

        mappings.fetch(jwk_kty.to_s) do |kty|
          raise JWT::JWKError, "Key type #{kty} not supported"
        end.import(jwk_data)
      end

      def create_from(keypair, kid = nil)
        mappings.fetch(keypair.class) do |klass|
          raise JWT::JWKError, "Cannot create JWK from a #{klass.name}"
        end.new(keypair, kid)
      end

      def classes
        @mappings = nil # reset the cached mappings
        @classes ||= []
      end

      alias new create_from

      private

      def mappings
        @mappings ||= generate_mappings
      end

      def generate_mappings
        classes.each_with_object({}) do |klass, hash|
          next unless klass.const_defined?('KTYS')
          Array(klass::KTYS).each do |kty|
            hash[kty] = klass
          end
        end
      end
    end
  end
end

require_relative 'jwk/key_base'
require_relative 'jwk/ec'
require_relative 'jwk/rsa'
require_relative 'jwk/hmac'
