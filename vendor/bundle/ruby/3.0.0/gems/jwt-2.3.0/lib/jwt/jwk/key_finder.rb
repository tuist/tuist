# frozen_string_literal: true

module JWT
  module JWK
    class KeyFinder
      def initialize(options)
        jwks_or_loader = options[:jwks]
        @jwks          = jwks_or_loader if jwks_or_loader.is_a?(Hash)
        @jwk_loader    = jwks_or_loader if jwks_or_loader.respond_to?(:call)
      end

      def key_for(kid)
        raise ::JWT::DecodeError, 'No key id (kid) found from token headers' unless kid

        jwk = resolve_key(kid)

        raise ::JWT::DecodeError, 'No keys found in jwks' if jwks_keys.empty?
        raise ::JWT::DecodeError, "Could not find public key for kid #{kid}" unless jwk

        ::JWT::JWK.import(jwk).keypair
      end

      private

      def resolve_key(kid)
        jwk = find_key(kid)

        return jwk if jwk

        if reloadable?
          load_keys(invalidate: true)
          return find_key(kid)
        end

        nil
      end

      def jwks
        return @jwks if @jwks

        load_keys
        @jwks
      end

      def load_keys(opts = {})
        @jwks = @jwk_loader.call(opts)
      end

      def jwks_keys
        Array(jwks[:keys] || jwks['keys'])
      end

      def find_key(kid)
        jwks_keys.find { |key| (key[:kid] || key['kid']) == kid }
      end

      def reloadable?
        @jwk_loader
      end
    end
  end
end
