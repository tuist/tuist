# frozen_string_literal: true

class UserCreateService < ApplicationService
  attr_reader :email, :password, :skip_confirmation

  def initialize(email:, password: nil, skip_confirmation: false)
    super()
    @email = email
    @password = password
    @skip_confirmation = skip_confirmation
  end

  def call
    ActiveRecord::Base.transaction do
      user = User.find_or_initialize_by(email: email) do |user|
        user.password = if password.nil?
          Devise.friendly_token.first(16)
        else
          password
        end
      end
      if skip_confirmation
        user.skip_confirmation!
      end
      user.save!
      Analytics.on_user_authentication(email)
      user
    end
  end
end
