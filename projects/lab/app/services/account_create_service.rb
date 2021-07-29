# frozen_string_literal: true
class AccountCreateService < ApplicationService
  attr_reader :owner, :name

  def initialize(owner:, name:)
    @owner = owner
    @name = name
    super()
  end

  def call
    account = Account.new(owner: owner, name: name)
    account.save!
    account
  end
end
