# frozen_string_literal: true

require 'jwt/security_utils'
require 'openssl'
require 'jwt/algos'
begin
  require 'rbnacl'
rescue LoadError
  raise if defined?(RbNaCl)
end

# JWT::Signature module
module JWT
  # Signature logic for JWT
  module Signature
    extend self
    ToSign = Struct.new(:algorithm, :msg, :key)
    ToVerify = Struct.new(:algorithm, :public_key, :signing_input, :signature)

    def sign(algorithm, msg, key)
      algo, code = Algos.find(algorithm)
      algo.sign ToSign.new(code, msg, key)
    end

    def verify(algorithm, key, signing_input, signature)
      return true if algorithm.casecmp('none').zero?

      raise JWT::DecodeError, 'No verification key available' unless key

      algo, code = Algos.find(algorithm)
      verified = algo.verify(ToVerify.new(code, key, signing_input, signature))
      raise(JWT::VerificationError, 'Signature verification raised') unless verified
    rescue OpenSSL::PKey::PKeyError
      raise JWT::VerificationError, 'Signature verification raised'
    ensure
      OpenSSL.errors.clear
    end
  end
end
