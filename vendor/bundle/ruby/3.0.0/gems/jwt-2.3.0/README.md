# JWT

[![Gem Version](https://badge.fury.io/rb/jwt.svg)](https://badge.fury.io/rb/jwt)
[![Build Status](https://github.com/jwt/ruby-jwt/workflows/test/badge.svg?branch=master)](https://github.com/jwt/ruby-jwt/actions)
[![Code Climate](https://codeclimate.com/github/jwt/ruby-jwt/badges/gpa.svg)](https://codeclimate.com/github/jwt/ruby-jwt)
[![Test Coverage](https://codeclimate.com/github/jwt/ruby-jwt/badges/coverage.svg)](https://codeclimate.com/github/jwt/ruby-jwt/coverage)
[![Issue Count](https://codeclimate.com/github/jwt/ruby-jwt/badges/issue_count.svg)](https://codeclimate.com/github/jwt/ruby-jwt)
[![SourceLevel](https://app.sourcelevel.io/github/jwt/-/ruby-jwt.svg)](https://app.sourcelevel.io/github/jwt/-/ruby-jwt)

A ruby implementation of the [RFC 7519 OAuth JSON Web Token (JWT)](https://tools.ietf.org/html/rfc7519) standard.

If you have further questions related to development or usage, join us: [ruby-jwt google group](https://groups.google.com/forum/#!forum/ruby-jwt).

## Announcements

* Ruby 1.9.3 support was dropped at December 31st, 2016.
* Version 1.5.3 yanked. See: [#132](https://github.com/jwt/ruby-jwt/issues/132) and [#133](https://github.com/jwt/ruby-jwt/issues/133)

## Sponsors

|Logo|Message|
|-|-|
|![auth0 logo](https://user-images.githubusercontent.com/83319/31722733-de95bbde-b3ea-11e7-96bf-4f4e8f915588.png)|If you want to quickly add secure token-based authentication to Ruby projects, feel free to check Auth0's Ruby SDK and free plan at [auth0.com/developers](https://auth0.com/developers?utm_source=GHsponsor&utm_medium=GHsponsor&utm_campaign=rubyjwt&utm_content=auth)|

## Installing

### Using Rubygems:
```bash
gem install jwt
```

### Using Bundler:
Add the following to your Gemfile
```
gem 'jwt'
```
And run `bundle install`

## Algorithms and Usage

The JWT spec supports NONE, HMAC, RSASSA, ECDSA and RSASSA-PSS algorithms for cryptographic signing. Currently the jwt gem supports NONE, HMAC, RSASSA and ECDSA. If you are using cryptographic signing, you need to specify the algorithm in the options hash whenever you call JWT.decode to ensure that an attacker [cannot bypass the algorithm verification step](https://auth0.com/blog/critical-vulnerabilities-in-json-web-token-libraries/). **It is strongly recommended that you hard code the algorithm, as you may leave yourself vulnerable by dynamically picking the algorithm**

See: [ JSON Web Algorithms (JWA) 3.1. "alg" (Algorithm) Header Parameter Values for JWS](https://tools.ietf.org/html/rfc7518#section-3.1)

**NONE**

* none - unsigned token

```ruby
require 'jwt'

payload = { data: 'test' }

# IMPORTANT: set nil as password parameter
token = JWT.encode payload, nil, 'none'

# eyJhbGciOiJub25lIn0.eyJkYXRhIjoidGVzdCJ9.
puts token

# Set password to nil and validation to false otherwise this won't work
decoded_token = JWT.decode token, nil, false

# Array
# [
#   {"data"=>"test"}, # payload
#   {"alg"=>"none"} # header
# ]
puts decoded_token
```

**HMAC**

* HS256 - HMAC using SHA-256 hash algorithm
* HS512256 - HMAC using SHA-512-256 hash algorithm (only available with RbNaCl; see note below)
* HS384 - HMAC using SHA-384 hash algorithm
* HS512 - HMAC using SHA-512 hash algorithm

```ruby
# The secret must be a string. A JWT::DecodeError will be raised if it isn't provided.
hmac_secret = 'my$ecretK3y'

token = JWT.encode payload, hmac_secret, 'HS256'

# eyJhbGciOiJIUzI1NiJ9.eyJkYXRhIjoidGVzdCJ9.pNIWIL34Jo13LViZAJACzK6Yf0qnvT_BuwOxiMCPE-Y
puts token

decoded_token = JWT.decode token, hmac_secret, true, { algorithm: 'HS256' }

# Array
# [
#   {"data"=>"test"}, # payload
#   {"alg"=>"HS256"} # header
# ]
puts decoded_token
```

Note: If [RbNaCl](https://github.com/cryptosphere/rbnacl) is loadable, ruby-jwt will use it for HMAC-SHA256, HMAC-SHA512-256, and HMAC-SHA512. RbNaCl enforces a maximum key size of 32 bytes for these algorithms.

[RbNaCl](https://github.com/cryptosphere/rbnacl) requires
[libsodium](https://github.com/jedisct1/libsodium), it can be installed
on MacOS with `brew install libsodium`.

**RSA**

* RS256 - RSA using SHA-256 hash algorithm
* RS384 - RSA using SHA-384 hash algorithm
* RS512 - RSA using SHA-512 hash algorithm

```ruby
rsa_private = OpenSSL::PKey::RSA.generate 2048
rsa_public = rsa_private.public_key

token = JWT.encode payload, rsa_private, 'RS256'

# eyJhbGciOiJSUzI1NiJ9.eyJkYXRhIjoidGVzdCJ9.GplO4w1spRgvEJQ3-FOtZr-uC8L45Jt7SN0J4woBnEXG_OZBSNcZjAJWpjadVYEe2ev3oUBFDYM1N_-0BTVeFGGYvMewu8E6aMjSZvOpf1cZBew-Vt4poSq7goG2YRI_zNPt3af2lkPqXD796IKC5URrEvcgF5xFQ-6h07XRDpSRx1ECrNsUOt7UM3l1IB4doY11GzwQA5sHDTmUZ0-kBT76ZMf12Srg_N3hZwphxBtudYtN5VGZn420sVrQMdPE_7Ni3EiWT88j7WCr1xrF60l8sZT3yKCVleG7D2BEXacTntB7GktBv4Xo8OKnpwpqTpIlC05dMowMkz3rEAAYbQ
puts token

decoded_token = JWT.decode token, rsa_public, true, { algorithm: 'RS256' }

# Array
# [
#   {"data"=>"test"}, # payload
#   {"alg"=>"RS256"} # header
# ]
puts decoded_token
```

**ECDSA**

* ES256 - ECDSA using P-256 and SHA-256
* ES384 - ECDSA using P-384 and SHA-384
* ES512 - ECDSA using P-521 and SHA-512

```ruby
ecdsa_key = OpenSSL::PKey::EC.new 'prime256v1'
ecdsa_key.generate_key
ecdsa_public = OpenSSL::PKey::EC.new ecdsa_key
ecdsa_public.private_key = nil

token = JWT.encode payload, ecdsa_key, 'ES256'

# eyJhbGciOiJFUzI1NiJ9.eyJkYXRhIjoidGVzdCJ9.AlLW--kaF7EX1NMX9WJRuIW8NeRJbn2BLXHns7Q5TZr7Hy3lF6MOpMlp7GoxBFRLISQ6KrD0CJOrR8aogEsPeg
puts token

decoded_token = JWT.decode token, ecdsa_public, true, { algorithm: 'ES256' }

# Array
# [
#    {"test"=>"data"}, # payload
#    {"alg"=>"ES256"} # header
# ]
puts decoded_token
```

**EDDSA**

In order to use this algorithm you need to add the `RbNaCl` gem to you `Gemfile`.

```ruby
gem 'rbnacl'
```

For more detailed installation instruction check the official [repository](https://github.com/cryptosphere/rbnacl) on GitHub.

* ED25519

```ruby
private_key = RbNaCl::Signatures::Ed25519::SigningKey.new('abcdefghijklmnopqrstuvwxyzABCDEF')
public_key = private_key.verify_key
token = JWT.encode payload, private_key, 'ED25519'

# eyJhbGciOiJFRDI1NTE5In0.eyJkYXRhIjoidGVzdCJ9.6xIztXyOupskddGA_RvKU76V9b2dCQUYhoZEVFnRimJoPYIzZ2Fm47CWw8k2NTCNpgfAuxg9OXjaiVK7MvrbCQ
puts token

decoded_token = JWT.decode token, public_key, true, { algorithm: 'ED25519' }
# Array
# [
#  {"test"=>"data"}, # payload
#  {"alg"=>"ED25519"} # header
# ]

```

**RSASSA-PSS**

In order to use this algorithm you need to add the `openssl` gem to you `Gemfile` with a version greater or equal to `2.1`.

```ruby
gem 'openssl', '~> 2.1'
```

* PS256 - RSASSA-PSS using SHA-256 hash algorithm
* PS384 - RSASSA-PSS using SHA-384 hash algorithm
* PS512 - RSASSA-PSS using SHA-512 hash algorithm

```ruby
rsa_private = OpenSSL::PKey::RSA.generate 2048
rsa_public = rsa_private.public_key

token = JWT.encode payload, rsa_private, 'PS256'

# eyJhbGciOiJQUzI1NiJ9.eyJkYXRhIjoidGVzdCJ9.KEmqagMUHM-NcmXo6818ZazVTIAkn9qU9KQFT1c5Iq91n0KRpAI84jj4ZCdkysDlWokFs3Dmn4MhcXP03oJKLFgnoPL40_Wgg9iFr0jnIVvnMUp1kp2RFUbL0jqExGTRA3LdAhuvw6ZByGD1bkcWjDXygjQw-hxILrT1bENjdr0JhFd-cB0-ps5SB0mwhFNcUw-OM3Uu30B1-mlFaelUY8jHJYKwLTZPNxHzndt8RGXF8iZLp7dGb06HSCKMcVzhASGMH4ZdFystRe2hh31cwcvnl-Eo_D4cdwmpN3Abhk_8rkxawQJR3duh8HNKc4AyFPo7SabEaSu2gLnLfN3yfg
puts token

decoded_token = JWT.decode token, rsa_public, true, { algorithm: 'PS256' }

# Array
# [
#   {"data"=>"test"}, # payload
#   {"alg"=>"PS256"} # header
# ]
puts decoded_token
```

## Support for reserved claim names
JSON Web Token defines some reserved claim names and defines how they should be
used. JWT supports these reserved claim names:

 - 'exp' (Expiration Time) Claim
 - 'nbf' (Not Before Time) Claim
 - 'iss' (Issuer) Claim
 - 'aud' (Audience) Claim
 - 'jti' (JWT ID) Claim
 - 'iat' (Issued At) Claim
 - 'sub' (Subject) Claim

## Add custom header fields
Ruby-jwt gem supports custom [header fields](https://tools.ietf.org/html/rfc7519#section-5)
To add custom header fields you need to pass `header_fields` parameter

```ruby
token = JWT.encode payload, key, algorithm='HS256', header_fields={}
```

**Example:**

```ruby
require 'jwt'

payload = { data: 'test' }

# IMPORTANT: set nil as password parameter
token = JWT.encode payload, nil, 'none', { typ: 'JWT' }

# eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJkYXRhIjoidGVzdCJ9.
puts token

# Set password to nil and validation to false otherwise this won't work
decoded_token = JWT.decode token, nil, false

# Array
# [
#   {"data"=>"test"}, # payload
#   {"typ"=>"JWT", "alg"=>"none"} # header
# ]
puts decoded_token
```

### Expiration Time Claim

From [Oauth JSON Web Token 4.1.4. "exp" (Expiration Time) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.4):

> The `exp` (expiration time) claim identifies the expiration time on or after which the JWT MUST NOT be accepted for processing. The processing of the `exp` claim requires that the current date/time MUST be before the expiration date/time listed in the `exp` claim. Implementers MAY provide for some small `leeway`, usually no more than a few minutes, to account for clock skew. Its value MUST be a number containing a ***NumericDate*** value. Use of this claim is OPTIONAL.

**Handle Expiration Claim**

```ruby
exp = Time.now.to_i + 4 * 3600
exp_payload = { data: 'data', exp: exp }

token = JWT.encode exp_payload, hmac_secret, 'HS256'

begin
  decoded_token = JWT.decode token, hmac_secret, true, { algorithm: 'HS256' }
rescue JWT::ExpiredSignature
  # Handle expired token, e.g. logout user or deny access
end
```

The Expiration Claim verification can be disabled.
```ruby
# Decode token without raising JWT::ExpiredSignature error
JWT.decode token, hmac_secret, true, { verify_expiration: false, algorithm: 'HS256' }
```

**Adding Leeway**

```ruby
exp = Time.now.to_i - 10
leeway = 30 # seconds

exp_payload = { data: 'data', exp: exp }

# build expired token
token = JWT.encode exp_payload, hmac_secret, 'HS256'

begin
  # add leeway to ensure the token is still accepted
  decoded_token = JWT.decode token, hmac_secret, true, { exp_leeway: leeway, algorithm: 'HS256' }
rescue JWT::ExpiredSignature
  # Handle expired token, e.g. logout user or deny access
end
```

### Not Before Time Claim

From [Oauth JSON Web Token 4.1.5. "nbf" (Not Before) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.5):

> The `nbf` (not before) claim identifies the time before which the JWT MUST NOT be accepted for processing. The processing of the `nbf` claim requires that the current date/time MUST be after or equal to the not-before date/time listed in the `nbf` claim. Implementers MAY provide for some small `leeway`, usually no more than a few minutes, to account for clock skew. Its value MUST be a number containing a ***NumericDate*** value. Use of this claim is OPTIONAL.

**Handle Not Before Claim**

```ruby
nbf = Time.now.to_i - 3600
nbf_payload = { data: 'data', nbf: nbf }

token = JWT.encode nbf_payload, hmac_secret, 'HS256'

begin
  decoded_token = JWT.decode token, hmac_secret, true, { algorithm: 'HS256' }
rescue JWT::ImmatureSignature
  # Handle invalid token, e.g. logout user or deny access
end
```

The Not Before Claim verification can be disabled.
```ruby
# Decode token without raising JWT::ImmatureSignature error
JWT.decode token, hmac_secret, true, { verify_not_before: false, algorithm: 'HS256' }
```

**Adding Leeway**

```ruby
nbf = Time.now.to_i + 10
leeway = 30

nbf_payload = { data: 'data', nbf: nbf }

# build expired token
token = JWT.encode nbf_payload, hmac_secret, 'HS256'

begin
  # add leeway to ensure the token is valid
  decoded_token = JWT.decode token, hmac_secret, true, { nbf_leeway: leeway, algorithm: 'HS256' }
rescue JWT::ImmatureSignature
  # Handle invalid token, e.g. logout user or deny access
end
```

### Issuer Claim

From [Oauth JSON Web Token 4.1.1. "iss" (Issuer) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.1):

> The `iss` (issuer) claim identifies the principal that issued the JWT. The processing of this claim is generally application specific. The `iss` value is a case-sensitive string containing a ***StringOrURI*** value. Use of this claim is OPTIONAL.

You can pass multiple allowed issuers as an Array, verification will pass if one of them matches the `iss` value in the payload.

```ruby
iss = 'My Awesome Company Inc. or https://my.awesome.website/'
iss_payload = { data: 'data', iss: iss }

token = JWT.encode iss_payload, hmac_secret, 'HS256'

begin
  # Add iss to the validation to check if the token has been manipulated
  decoded_token = JWT.decode token, hmac_secret, true, { iss: iss, verify_iss: true, algorithm: 'HS256' }
rescue JWT::InvalidIssuerError
  # Handle invalid token, e.g. logout user or deny access
end
```

### Audience Claim

From [Oauth JSON Web Token 4.1.3. "aud" (Audience) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.3):

> The `aud` (audience) claim identifies the recipients that the JWT is intended for. Each principal intended to process the JWT MUST identify itself with a value in the audience claim. If the principal processing the claim does not identify itself with a value in the `aud` claim when this claim is present, then the JWT MUST be rejected. In the general case, the `aud` value is an array of case-sensitive strings, each containing a ***StringOrURI*** value. In the special case when the JWT has one audience, the `aud` value MAY be a single case-sensitive string containing a ***StringOrURI*** value. The interpretation of audience values is generally application specific. Use of this claim is OPTIONAL.

```ruby
aud = ['Young', 'Old']
aud_payload = { data: 'data', aud: aud }

token = JWT.encode aud_payload, hmac_secret, 'HS256'

begin
  # Add aud to the validation to check if the token has been manipulated
  decoded_token = JWT.decode token, hmac_secret, true, { aud: aud, verify_aud: true, algorithm: 'HS256' }
rescue JWT::InvalidAudError
  # Handle invalid token, e.g. logout user or deny access
  puts 'Audience Error'
end
```

### JWT ID Claim

From [Oauth JSON Web Token 4.1.7. "jti" (JWT ID) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.7):

> The `jti` (JWT ID) claim provides a unique identifier for the JWT. The identifier value MUST be assigned in a manner that ensures that there is a negligible probability that the same value will be accidentally assigned to a different data object; if the application uses multiple issuers, collisions MUST be prevented among values produced by different issuers as well. The `jti` claim can be used to prevent the JWT from being replayed. The `jti` value is a case-sensitive string. Use of this claim is OPTIONAL.

```ruby
# Use the secret and iat to create a unique key per request to prevent replay attacks
jti_raw = [hmac_secret, iat].join(':').to_s
jti = Digest::MD5.hexdigest(jti_raw)
jti_payload = { data: 'data', iat: iat, jti: jti }

token = JWT.encode jti_payload, hmac_secret, 'HS256'

begin
  # If :verify_jti is true, validation will pass if a JTI is present
  #decoded_token = JWT.decode token, hmac_secret, true, { verify_jti: true, algorithm: 'HS256' }
  # Alternatively, pass a proc with your own code to check if the JTI has already been used
  decoded_token = JWT.decode token, hmac_secret, true, { verify_jti: proc { |jti| my_validation_method(jti) }, algorithm: 'HS256' }
  # or
  decoded_token = JWT.decode token, hmac_secret, true, { verify_jti: proc { |jti, payload| my_validation_method(jti, payload) }, algorithm: 'HS256' }
rescue JWT::InvalidJtiError
  # Handle invalid token, e.g. logout user or deny access
  puts 'Error'
end
```

### Issued At Claim

From [Oauth JSON Web Token 4.1.6. "iat" (Issued At) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.6):

> The `iat` (issued at) claim identifies the time at which the JWT was issued. This claim can be used to determine the age of the JWT. The `leeway` option is not taken into account when verifying this claim. The `iat_leeway` option was removed in version 2.2.0. Its value MUST be a number containing a ***NumericDate*** value. Use of this claim is OPTIONAL.

**Handle Issued At Claim**

```ruby
iat = Time.now.to_i
iat_payload = { data: 'data', iat: iat }

token = JWT.encode iat_payload, hmac_secret, 'HS256'

begin
  # Add iat to the validation to check if the token has been manipulated
  decoded_token = JWT.decode token, hmac_secret, true, { verify_iat: true, algorithm: 'HS256' }
rescue JWT::InvalidIatError
  # Handle invalid token, e.g. logout user or deny access
end
```

### Subject Claim

From [Oauth JSON Web Token 4.1.2. "sub" (Subject) Claim](https://tools.ietf.org/html/rfc7519#section-4.1.2):

> The `sub` (subject) claim identifies the principal that is the subject of the JWT. The Claims in a JWT are normally statements about the subject. The subject value MUST either be scoped to be locally unique in the context of the issuer or be globally unique. The processing of this claim is generally application specific. The sub value is a case-sensitive string containing a ***StringOrURI*** value. Use of this claim is OPTIONAL.

```ruby
sub = 'Subject'
sub_payload = { data: 'data', sub: sub }

token = JWT.encode sub_payload, hmac_secret, 'HS256'

begin
  # Add sub to the validation to check if the token has been manipulated
  decoded_token = JWT.decode token, hmac_secret, true, { sub: sub, verify_sub: true, algorithm: 'HS256' }
rescue JWT::InvalidSubError
  # Handle invalid token, e.g. logout user or deny access
end
```

### Finding a Key

To dynamically find the key for verifying the JWT signature, pass a block to the decode block. The block receives headers and the original payload as parameters. It should return with the key to verify the signature that was used to sign the JWT.

```ruby
issuers = %w[My_Awesome_Company1 My_Awesome_Company2]
iss_payload = { data: 'data', iss: issuers.first }

secrets = { issuers.first => hmac_secret, issuers.last => 'hmac_secret2' }

token = JWT.encode iss_payload, hmac_secret, 'HS256'

begin
  # Add iss to the validation to check if the token has been manipulated
  decoded_token = JWT.decode(token, nil, true, { iss: issuers, verify_iss: true, algorithm: 'HS256' }) do |_headers, payload|
    secrets[payload['iss']]
  end
rescue JWT::InvalidIssuerError
  # Handle invalid token, e.g. logout user or deny access
end
```

### Required Claims

You can specify claims that must be present for decoding to be successful. JWT::MissingRequiredClaim will be raised if any are missing
```ruby
# Will raise a JWT::ExpiredSignature error if the 'exp' claim is absent
JWT.decode token, hmac_secret, true, { required_claims: ['exp'], algorithm: 'HS256' }
```

### JSON Web Key (JWK)

JWK is a JSON structure representing a cryptographic key. Currently only supports RSA public keys.

```ruby
jwk = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048), "optional-kid")
payload, headers = { data: 'data' }, { kid: jwk.kid }

token = JWT.encode(payload, jwk.keypair, 'RS512', headers)

# The jwk loader would fetch the set of JWKs from a trusted source
jwk_loader = ->(options) do
  @cached_keys = nil if options[:invalidate] # need to reload the keys
  @cached_keys ||= { keys: [jwk.export] }
end

begin
  JWT.decode(token, nil, true, { algorithms: ['RS512'], jwks: jwk_loader})
rescue JWT::JWKError
  # Handle problems with the provided JWKs
rescue JWT::DecodeError
  # Handle other decode related issues e.g. no kid in header, no matching public key found etc.
end
```

or by passing JWK as a simple Hash

```
jwks = { keys: [{ ... }] } # keys accepts both of string and symbol
JWT.decode(token, nil, true, { algorithms: ['RS512'], jwks: jwks})
```

### Importing and exporting JSON Web Keys

The ::JWT::JWK class can be used to import and export both the public key (default behaviour) and the private key. To include the private key in the export pass the  `include_private` parameter to the export method.

```ruby
jwk = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048))

jwk_hash = jwk.export
jwk_hash_with_private_key = jwk.export(include_private: true)
```

# Development and Tests

We depend on [Bundler](http://rubygems.org/gems/bundler) for defining gemspec and performing releases to rubygems.org, which can be done with

```bash
rake release
```

The tests are written with rspec. [Appraisal](https://github.com/thoughtbot/appraisal) is used to ensure compatibility with 3rd party dependencies providing cryptographic features.

```bash
bundle install
bundle exec appraisal rake test
```

**If you want a release cut with your PR, please include a version bump according to [Semantic Versioning](http://semver.org/)**

## Contributors

See `AUTHORS` file.

## License

See `LICENSE` file.
