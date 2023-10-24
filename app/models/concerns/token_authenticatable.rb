# frozen_string_literal: true

module TokenAuthenticatable
  extend ActiveSupport::Concern

  Token = Struct.new(:model_name, :id, :token) do
    class << self
      def decode(encoded)
        decoded = Base64.urlsafe_decode64(encoded)
        model_name, id, token = decoded.split(":")

        new(model_name, id, token)
      end
    end

    def valid?
      [model_name, id, token].all?(&:present?)
    end

    def encode
      Base64.urlsafe_encode64(to_a.join(":"), padding: false)
    end
  end

  included do
    before_save :ensure_token_presence
  end

  class_methods do
    attr_reader :token_property

    def autogenerates_token(token_property)
      @token_property = token_property
    end
  end

  def encoded_token
    return if self.class.token_property.nil?

    Token.new(
      self.class.name,
      id,
      send(self.class.token_property),
    ).encode
  end

  private

  def ensure_token_presence
    return if self.class.token_property.nil?

    token = send(self.class.token_property)
    if token.blank?
      send("#{self.class.token_property}=", generate_token)
    end
  end

  def generate_token
    loop do
      token = Devise.friendly_token(30)
      query = { self.class.token_property => token }
      break token unless self.class.exists?(**query)
    end
  end
end
