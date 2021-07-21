# typed: ignore
# frozen_string_literal: true

# Find an existing user or create a user and authorizations
# schema of auth https://github.com/omniauth/omniauth/wiki/Auth-Hash-Schema
class UserCreateService < ApplicationService
  attr_reader :auth

  def initialize(auth:)
    @auth = auth
    super()
  end

  def call
    # Returning users
    authorization = Authorization.find_by(provider: auth.provider, uid: auth.uid)
    return authorization.user if authorization

    email = auth.info.email
    nickname = auth.info.nickname

    # Match existing users
    existing_user = User.find_for_database_authentication(email: email.downcase)
    if existing_user
      AuthorizationAddService.call(user: existing_user, data: auth)
      return existing_user
    end

    create_new_user_from_oauth(auth: auth, email: email, nickname: nickname)
  end

  private
    def create_new_user_from_oauth(auth:, email:, nickname:)
      ActiveRecord::Base.transaction do
        # User
        password = Devise.friendly_token[0, 20]
        user = User.new({ email: email, password: password })
        AuthorizationAddService.call(user: user, data: auth)
        user.save!

        AccountCreateService.call(
          owner: user,
          name: nickname
        )

        user
      end
    end
end
