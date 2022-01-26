require_relative './error'

module JWT
  class ClaimsValidator
    NUMERIC_CLAIMS = %i[
      exp
      iat
      nbf
    ].freeze

    def initialize(payload)
      @payload = payload.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    def validate!
      validate_numeric_claims

      true
    end

    private

    def validate_numeric_claims
      NUMERIC_CLAIMS.each do |claim|
        validate_is_numeric(claim) if @payload.key?(claim)
      end
    end

    def validate_is_numeric(claim)
      return if @payload[claim].is_a?(Numeric)

      raise InvalidPayload, "#{claim} claim must be a Numeric value but it is a #{@payload[claim].class}"
    end
  end
end
