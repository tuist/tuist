# frozen_string_literal: true

require 'jwt/algos/hmac'
require 'jwt/algos/eddsa'
require 'jwt/algos/ecdsa'
require 'jwt/algos/rsa'
require 'jwt/algos/ps'
require 'jwt/algos/none'
require 'jwt/algos/unsupported'

# JWT::Signature module
module JWT
  # Signature logic for JWT
  module Algos
    extend self

    ALGOS = [
      Algos::Hmac,
      Algos::Ecdsa,
      Algos::Rsa,
      Algos::Eddsa,
      Algos::Ps,
      Algos::None,
      Algos::Unsupported
    ].freeze

    def find(algorithm)
      indexed[algorithm && algorithm.downcase]
    end

    private

    def indexed
      @indexed ||= begin
        fallback = [Algos::Unsupported, nil]
        ALGOS.each_with_object(Hash.new(fallback)) do |alg, hash|
          alg.const_get(:SUPPORTED).each do |code|
            hash[code.downcase] = [alg, code]
          end
        end
      end
    end
  end
end
