# frozen_string_literal: true

class UserCreateService < ApplicationService
  attr_reader :email, :provider, :id_in_provider

  def initialize(email:, provider:, id_in_provider:)
    super()
    @email = email
    @provider = provider
    @id_in_provider = id_in_provider
  end

  def call
    ActiveRecord::Base.transaction do
      oauth2_identity = Oauth2Identity.find_by(provider: provider, id_in_provider: id_in_provider)
      user_by_email = User.find_by(email: email)

      user = if oauth2_identity
        oauth2_identity.user
      # Before the existence of OAuth2 identities we have users in the database without identities.
      elsif user_by_email && !oauth2_identity
        Oauth2Identity.create!(provider: provider, id_in_provider: id_in_provider, user: user_by_email)
        user_by_email
      else
        user = User.new(email: email, password: Devise.friendly_token.first(16))
        user.skip_confirmation!
        user.save!
        Oauth2Identity.create!(provider: provider, id_in_provider: id_in_provider, user: user)
        user
      end
      Analytics.on_user_authentication(email)
      user
    end
  end
end
