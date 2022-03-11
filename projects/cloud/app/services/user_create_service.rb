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
        if password.nil?
          user.password = Devise.friendly_token.first(16)
        else
          user.password = password
        end
      end
      if skip_confirmation
        user.skip_confirmation!
      end
      user.save!
      user
    end
  end
end
