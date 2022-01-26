module JWT
  module Algos
    module Ps
      # RSASSA-PSS signing algorithms

      module_function

      SUPPORTED = %w[PS256 PS384 PS512].freeze

      def sign(to_sign)
        require_openssl!

        algorithm, msg, key = to_sign.values

        key_class = key.class

        raise EncodeError, "The given key is a #{key_class}. It has to be an OpenSSL::PKey::RSA instance." if key_class == String

        translated_algorithm = algorithm.sub('PS', 'sha')

        key.sign_pss(translated_algorithm, msg, salt_length: :digest, mgf1_hash: translated_algorithm)
      end

      def verify(to_verify)
        require_openssl!

        SecurityUtils.verify_ps(to_verify.algorithm, to_verify.public_key, to_verify.signing_input, to_verify.signature)
      end

      def require_openssl!
        if Object.const_defined?('OpenSSL')
          major, minor = OpenSSL::VERSION.split('.').first(2)

          unless major.to_i >= 2 && minor.to_i >= 1
            raise JWT::RequiredDependencyError, "You currently have OpenSSL #{OpenSSL::VERSION}. PS support requires >= 2.1"
          end
        else
          raise JWT::RequiredDependencyError, 'PS signing requires OpenSSL +2.1'
        end
      end
    end
  end
end
