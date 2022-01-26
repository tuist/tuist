# frozen_string_literal: true

require 'jwt/base64'
require 'jwt/json'
require 'jwt/decode'
require 'jwt/default_options'
require 'jwt/encode'
require 'jwt/error'
require 'jwt/jwk'

# JSON Web Token implementation
#
# Should be up to date with the latest spec:
# https://tools.ietf.org/html/rfc7519
module JWT
  include JWT::DefaultOptions

  module_function

  def encode(payload, key, algorithm = 'HS256', header_fields = {})
    Encode.new(payload: payload,
               key: key,
               algorithm: algorithm,
               headers: header_fields).segments
  end

  def decode(jwt, key = nil, verify = true, options = {}, &keyfinder)
    Decode.new(jwt, key, verify, DEFAULT_OPTIONS.merge(options), &keyfinder).decode_segments
  end
end
