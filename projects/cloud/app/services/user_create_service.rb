# frozen_string_literal: true

class UserCreateService < ApplicationService
  ACCOUNT_SUFFIX_LIMIT = 5

  module Error
    Base = Class.new(StandardError)
    CantObtainAccountName = Class.new(Base)
  end

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
        Account.create!(name: account_name, owner: user)
      end
      user.reload
    end
  end

  private
    def account_name(suffix: nil)
      name = email.split("@").first
      name = suffix.nil? ? name : name + suffix.to_s
      return name if Account.where(name: name).count == 0
      suffix = suffix.nil? ? 1 : suffix + 1
      raise Error::CantObtainAccountName if suffix == ACCOUNT_SUFFIX_LIMIT
      account_name(suffix: suffix)
    end
end
