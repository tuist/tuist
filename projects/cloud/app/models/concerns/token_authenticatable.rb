# frozen_string_literal: true

module TokenAuthenticatable
  extend ActiveSupport::Concern

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

    APITokenStrategy::Token.new(
      self.class.name,
      id,
      self.send(self.class.token_property),
    ).encode
  end

  private
    def ensure_token_presence
      return if self.class.token_property.nil?

      token = self.send(self.class.token_property)
      if token.blank?
        self.send("#{self.class.token_property}=", generate_token)
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
