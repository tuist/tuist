# frozen_string_literal: true

class ProjectFetchService < ApplicationService
  attr_reader :name, :account_name

  def initialize(name:, account_name:)
    super()
    @name = name
    @account_name = account_name
  end

  def call
    account = Account.find_by(name: account_name)
    Project.find_by(account_id: account.id, name: name)
  end
end
