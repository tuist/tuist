# frozen_string_literal: true

module JWT
  module JWK
    class RSA < KeyBase
      BINARY = 2
      KTY    = 'RSA'.freeze
      KTYS   = [KTY, OpenSSL::PKey::RSA].freeze
      RSA_KEY_ELEMENTS = %i[n e d p q dp dq qi].freeze

      def initialize(keypair, kid = nil)
        raise ArgumentError, 'keypair must be of type OpenSSL::PKey::RSA' unless keypair.is_a?(OpenSSL::PKey::RSA)
        super(keypair, kid || generate_kid(keypair.public_key))
      end

      def private?
        keypair.private?
      end

      def public_key
        keypair.public_key
      end

      def export(options = {})
        exported_hash = {
          kty: KTY,
          n: encode_open_ssl_bn(public_key.n),
          e: encode_open_ssl_bn(public_key.e),
          kid: kid
        }

        return exported_hash unless private? && options[:include_private] == true

        append_private_parts(exported_hash)
      end

      private

      def generate_kid(public_key)
        sequence = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer.new(public_key.n),
                                            OpenSSL::ASN1::Integer.new(public_key.e)])
        OpenSSL::Digest::SHA256.hexdigest(sequence.to_der)
      end

      def append_private_parts(the_hash)
        the_hash.merge(
          d: encode_open_ssl_bn(keypair.d),
          p: encode_open_ssl_bn(keypair.p),
          q: encode_open_ssl_bn(keypair.q),
          dp: encode_open_ssl_bn(keypair.dmp1),
          dq: encode_open_ssl_bn(keypair.dmq1),
          qi: encode_open_ssl_bn(keypair.iqmp)
        )
      end

      def encode_open_ssl_bn(key_part)
        ::JWT::Base64.url_encode(key_part.to_s(BINARY))
      end

      class << self
        def import(jwk_data)
          pkey_params = jwk_attributes(jwk_data, *RSA_KEY_ELEMENTS) do |value|
            decode_open_ssl_bn(value)
          end
          kid = jwk_attributes(jwk_data, :kid)[:kid]
          self.new(rsa_pkey(pkey_params), kid)
        end

        private

        def jwk_attributes(jwk_data, *attributes)
          attributes.each_with_object({}) do |attribute, hash|
            value = jwk_data[attribute] || jwk_data[attribute.to_s]
            value = yield(value) if block_given?
            hash[attribute] = value
          end
        end

        def rsa_pkey(rsa_parameters)
          raise JWT::JWKError, 'Key format is invalid for RSA' unless rsa_parameters[:n] && rsa_parameters[:e]

          populate_key(OpenSSL::PKey::RSA.new, rsa_parameters)
        end

        if OpenSSL::PKey::RSA.new.respond_to?(:set_key)
          def populate_key(rsa_key, rsa_parameters)
            rsa_key.set_key(rsa_parameters[:n], rsa_parameters[:e], rsa_parameters[:d])
            rsa_key.set_factors(rsa_parameters[:p], rsa_parameters[:q]) if rsa_parameters[:p] && rsa_parameters[:q]
            rsa_key.set_crt_params(rsa_parameters[:dp], rsa_parameters[:dq], rsa_parameters[:qi]) if rsa_parameters[:dp] && rsa_parameters[:dq] && rsa_parameters[:qi]
            rsa_key
          end
        else
          def populate_key(rsa_key, rsa_parameters)
            rsa_key.n = rsa_parameters[:n]
            rsa_key.e = rsa_parameters[:e]
            rsa_key.d = rsa_parameters[:d] if rsa_parameters[:d]
            rsa_key.p = rsa_parameters[:p] if rsa_parameters[:p]
            rsa_key.q = rsa_parameters[:q] if rsa_parameters[:q]
            rsa_key.dmp1 = rsa_parameters[:dp] if rsa_parameters[:dp]
            rsa_key.dmq1 = rsa_parameters[:dq] if rsa_parameters[:dq]
            rsa_key.iqmp = rsa_parameters[:qi] if rsa_parameters[:qi]

            rsa_key
          end
        end

        def decode_open_ssl_bn(jwk_data)
          return nil unless jwk_data

          OpenSSL::BN.new(::JWT::Base64.url_decode(jwk_data), BINARY)
        end
      end
    end
  end
end
