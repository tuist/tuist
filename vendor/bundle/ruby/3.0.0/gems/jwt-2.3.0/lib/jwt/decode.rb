# frozen_string_literal: true

require 'json'

require 'jwt/signature'
require 'jwt/verify'
# JWT::Decode module
module JWT
  # Decoding logic for JWT
  class Decode
    def initialize(jwt, key, verify, options, &keyfinder)
      raise(JWT::DecodeError, 'Nil JSON web token') unless jwt
      @jwt = jwt
      @key = key
      @options = options
      @segments = jwt.split('.')
      @verify = verify
      @signature = ''
      @keyfinder = keyfinder
    end

    def decode_segments
      validate_segment_count!
      if @verify
        decode_crypto
        verify_signature
        verify_claims
      end
      raise(JWT::DecodeError, 'Not enough or too many segments') unless header && payload
      [payload, header]
    end

    private

    def verify_signature
      raise(JWT::IncorrectAlgorithm, 'An algorithm must be specified') if allowed_algorithms.empty?
      raise(JWT::IncorrectAlgorithm, 'Token is missing alg header') unless header['alg']
      raise(JWT::IncorrectAlgorithm, 'Expected a different algorithm') unless options_includes_algo_in_header?

      @key = find_key(&@keyfinder) if @keyfinder
      @key = ::JWT::JWK::KeyFinder.new(jwks: @options[:jwks]).key_for(header['kid']) if @options[:jwks]

      Signature.verify(header['alg'], @key, signing_input, @signature)
    end

    def options_includes_algo_in_header?
      allowed_algorithms.any? { |alg| alg.casecmp(header['alg']).zero? }
    end

    def allowed_algorithms
      # Order is very important - first check for string keys, next for symbols
      algos = if @options.key?('algorithm')
        @options['algorithm']
      elsif @options.key?(:algorithm)
        @options[:algorithm]
      elsif @options.key?('algorithms')
        @options['algorithms']
      elsif @options.key?(:algorithms)
        @options[:algorithms]
      else
        []
      end
      Array(algos)
    end

    def find_key(&keyfinder)
      key = (keyfinder.arity == 2 ? yield(header, payload) : yield(header))
      raise JWT::DecodeError, 'No verification key available' unless key
      key
    end

    def verify_claims
      Verify.verify_claims(payload, @options)
      Verify.verify_required_claims(payload, @options)
    end

    def validate_segment_count!
      return if segment_length == 3
      return if !@verify && segment_length == 2 # If no verifying required, the signature is not needed
      return if segment_length == 2 && header['alg'] == 'none'

      raise(JWT::DecodeError, 'Not enough or too many segments')
    end

    def segment_length
      @segments.count
    end

    def decode_crypto
      @signature = JWT::Base64.url_decode(@segments[2] || '')
    end

    def header
      @header ||= parse_and_decode @segments[0]
    end

    def payload
      @payload ||= parse_and_decode @segments[1]
    end

    def signing_input
      @segments.first(2).join('.')
    end

    def parse_and_decode(segment)
      JWT::JSON.parse(JWT::Base64.url_decode(segment))
    rescue ::JSON::ParserError
      raise JWT::DecodeError, 'Invalid segment encoding'
    end
  end
end
