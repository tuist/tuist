# frozen_string_literal: true

class UserCreateService < ApplicationService
  attr_reader :email, :password

  def initialize(email:, password:)
    super()
    @email = email
    @password = password
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
      user.save!
      user
    end
  end
end
