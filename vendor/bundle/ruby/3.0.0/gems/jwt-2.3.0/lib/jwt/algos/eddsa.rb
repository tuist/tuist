module JWT
  module Algos
    module Eddsa
      module_function

      SUPPORTED = %w[ED25519 EdDSA].freeze

      def sign(to_sign)
        algorithm, msg, key = to_sign.values
        if key.class != RbNaCl::Signatures::Ed25519::SigningKey
          raise EncodeError, "Key given is a #{key.class} but has to be an RbNaCl::Signatures::Ed25519::SigningKey"
        end
        unless SUPPORTED.map(&:downcase).map(&:to_sym).include?(algorithm.downcase.to_sym)
          raise IncorrectAlgorithm, "payload algorithm is #{algorithm} but #{key.primitive} signing key was provided"
        end

        key.sign(msg)
      end

      def verify(to_verify)
        algorithm, public_key, signing_input, signature = to_verify.values
        unless SUPPORTED.map(&:downcase).map(&:to_sym).include?(algorithm.downcase.to_sym)
          raise IncorrectAlgorithm, "payload algorithm is #{algorithm} but #{key.primitive} signing key was provided"
        end
        raise DecodeError, "key given is a #{public_key.class} but has to be a RbNaCl::Signatures::Ed25519::VerifyKey" if public_key.class != RbNaCl::Signatures::Ed25519::VerifyKey
        public_key.verify(signature, signing_input)
      end
    end
  end
end
