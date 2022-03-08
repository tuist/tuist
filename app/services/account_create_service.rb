# frozen_string_literal: true

class AccountCreateService < ApplicationService
  ACCOUNT_SUFFIX_LIMIT = 5

  module Error
    Base = Class.new(StandardError)
    CantObtainAccountName = Class.new(Base)
  end

  attr_reader :name, :owner

  def initialize(name:, owner:)
    @name = name
    @owner = owner
    super()
  end

  def call
    Account.create!(
      name: account_name,
      owner: owner
    )
  end

  private
    def account_name(suffix: nil)
      name = suffix.nil? ? self.name : self.name + suffix.to_s
      return name if Account.where(name: name).count == 0

      suffix = suffix.nil? ? 1 : suffix + 1
      raise Error::CantObtainAccountName if suffix == ACCOUNT_SUFFIX_LIMIT

      account_name(suffix: suffix)
    end
end
