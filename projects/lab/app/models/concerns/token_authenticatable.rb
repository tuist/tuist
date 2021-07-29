# frozen_string_literal: true

module TokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_save :ensure_authentication_token
  end

  class_methods do
    attr_reader :authentication_token_attribute

    def attr_authentication_token(attribute)
      @authentication_token_attribute = attribute
    end
  end

  def authentication_token
    send(self.class.authentication_token_attribute.to_s)
  end

  def authentication_token=(token)
    send("#{self.class.authentication_token_attribute}=", token)
  end

  def encoded_authentication_token
    ApiTokenStrategy::Token.new(
      self.class.name,
      id,
      authentication_token,
    ).encode
  end

  private
    def ensure_authentication_token
      if authentication_token.blank?
        self.authentication_token = generate_authentication_token
      end
    end

    def generate_authentication_token
      loop do
        token = Devise.friendly_token(30)
        query = { self.class.authentication_token_attribute.to_sym => token }
        break token unless self.class.exists?(query)
      end
    end
end
