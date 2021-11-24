# frozen_string_literal: true

class UserCreateService < ApplicationService
  attr_reader :email

  def initialize(email:)
    super()
    @email = email
  end

  def call
    ActiveRecord::Base.transaction do
      user = User.find_or_create_by!(email: email) do |user|
        user.password = Devise.friendly_token.first(16)
      end
      if user.account.nil?
        AccountCreateService.call(
          name: email.split("@").first,
          owner: user
        )
      end
      user.reload
    end
  end


end
