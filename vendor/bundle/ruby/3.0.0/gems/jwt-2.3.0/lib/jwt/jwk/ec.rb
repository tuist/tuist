# frozen_string_literal: true

require 'forwardable'

module JWT
  module JWK
    class EC < KeyBase
      extend Forwardable
      def_delegators :@keypair, :public_key

      KTY    = 'EC'.freeze
      KTYS   = [KTY, OpenSSL::PKey::EC].freeze
      BINARY = 2

      def initialize(keypair, kid = nil)
        raise ArgumentError, 'keypair must be of type OpenSSL::PKey::EC' unless keypair.is_a?(OpenSSL::PKey::EC)

        kid ||= generate_kid(keypair)
        super(keypair, kid)
      end

      def private?
        @keypair.private_key?
      end

      def export(options = {})
        crv, x_octets, y_octets = keypair_components(keypair)
        exported_hash = {
          kty: KTY,
          crv: crv,
          x: encode_octets(x_octets),
          y: encode_octets(y_octets),
          kid: kid
        }
        return exported_hash unless private? && options[:include_private] == true

        append_private_parts(exported_hash)
      end

      private

      def append_private_parts(the_hash)
        octets = keypair.private_key.to_bn.to_s(BINARY)
        the_hash.merge(
          d: encode_octets(octets)
        )
      end

      def generate_kid(ec_keypair)
        _crv, x_octets, y_octets = keypair_components(ec_keypair)
        sequence = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(x_octets, BINARY)),
                                            OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(y_octets, BINARY))])
        OpenSSL::Digest::SHA256.hexdigest(sequence.to_der)
      end

      def keypair_components(ec_keypair)
        encoded_point = ec_keypair.public_key.to_bn.to_s(BINARY)
        case ec_keypair.group.curve_name
        when 'prime256v1'
          crv = 'P-256'
          x_octets, y_octets = encoded_point.unpack('xa32a32')
        when 'secp384r1'
          crv = 'P-384'
          x_octets, y_octets = encoded_point.unpack('xa48a48')
        when 'secp521r1'
          crv = 'P-521'
          x_octets, y_octets = encoded_point.unpack('xa66a66')
        else
          raise JWT::JWKError, "Unsupported curve '#{ec_keypair.group.curve_name}'"
        end
        [crv, x_octets, y_octets]
      end

      def encode_octets(octets)
        ::JWT::Base64.url_encode(octets)
      end

      def encode_open_ssl_bn(key_part)
        ::JWT::Base64.url_encode(key_part.to_s(BINARY))
      end

      class << self
        def import(jwk_data)
          # See https://tools.ietf.org/html/rfc7518#section-6.2.1 for an
          # explanation of the relevant parameters.

          jwk_crv, jwk_x, jwk_y, jwk_d, jwk_kid = jwk_attrs(jwk_data, %i[crv x y d kid])
          raise JWT::JWKError, 'Key format is invalid for EC' unless jwk_crv && jwk_x && jwk_y

          new(ec_pkey(jwk_crv, jwk_x, jwk_y, jwk_d), jwk_kid)
        end

        def to_openssl_curve(crv)
          # The JWK specs and OpenSSL use different names for the same curves.
          # See https://tools.ietf.org/html/rfc5480#section-2.1.1.1 for some
          # pointers on different names for common curves.
          case crv
          when 'P-256' then 'prime256v1'
          when 'P-384' then 'secp384r1'
          when 'P-521' then 'secp521r1'
          else raise JWT::JWKError, 'Invalid curve provided'
          end
        end

        private

        def jwk_attrs(jwk_data, attrs)
          attrs.map do |attr|
            jwk_data[attr] || jwk_data[attr.to_s]
          end
        end

        def ec_pkey(jwk_crv, jwk_x, jwk_y, jwk_d)
          curve = to_openssl_curve(jwk_crv)

          x_octets = decode_octets(jwk_x)
          y_octets = decode_octets(jwk_y)

          key = OpenSSL::PKey::EC.new(curve)

          # The details of the `Point` instantiation are covered in:
          # - https://docs.ruby-lang.org/en/2.4.0/OpenSSL/PKey/EC.html
          # - https://www.openssl.org/docs/manmaster/man3/EC_POINT_new.html
          # - https://tools.ietf.org/html/rfc5480#section-2.2
          # - https://www.secg.org/SEC1-Ver-1.0.pdf
          # Section 2.3.3 of the last of these references specifies that the
          # encoding of an uncompressed point consists of the byte `0x04` followed
          # by the x value then the y value.
          point = OpenSSL::PKey::EC::Point.new(
            OpenSSL::PKey::EC::Group.new(curve),
            OpenSSL::BN.new([0x04, x_octets, y_octets].pack('Ca*a*'), 2)
          )

          key.public_key = point
          key.private_key = OpenSSL::BN.new(decode_octets(jwk_d), 2) if jwk_d

          key
        end

        def decode_octets(jwk_data)
          ::JWT::Base64.url_decode(jwk_data)
        end

        def decode_open_ssl_bn(jwk_data)
          OpenSSL::BN.new(::JWT::Base64.url_decode(jwk_data), BINARY)
        end
      end
    end
  end
end
