# frozen_string_literal: true

class APITokenStrategy < Devise::Strategies::Base
  Token = Struct.new(:model_name, :id, :token) do
    def self.decode(encoded)
      decoded = Base64.urlsafe_decode64(encoded)
      model_name, id, token = decoded.split(":")

      new(model_name, id, token)
    end

    def valid?
      [model_name, id, token].all?(&:present?)
    end

    def encode
      Base64.urlsafe_encode64(to_a.join(":"), padding: false)
    end
  end

  def valid?
    encoded_token.present?
  end

  def authenticate!
    return fail! unless token_format_valid?
    return fail! unless scope_match?
    return fail! unless token_match?

    skip_trackable

    success!(model_object)
  end

  def store?
    false
  end

  def clean_up_csrf?
    false
  end

  private
    def skip_trackable
      env["devise.skip_trackable"] = true
    end

    def fail!
      super("invalid token")
    end

    def token_format_valid?
      decoded_token.valid?
    rescue ArgumentError
      false
    end

    def scope_match?
      model.name == decoded_token.model_name
    end

    def model_object
      @model_object ||= model.find(decoded_token.id)
    end

    def token_match?
      Devise.secure_compare(model_object&.authentication_token, decoded_token.token)
    end

    def model
      mapping.to
    end

    def decoded_token
      @decoded_token ||= Token.decode(encoded_token)
    end

    def encoded_token
      request.headers["Authorization"].to_s.remove("Bearer ")
    end
end
