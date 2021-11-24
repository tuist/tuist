# frozen_string_literal: true

class UserProjectsFetchService < ApplicationService
  attr_reader :user

  def initialize(user:)
    super()
    @user = user
  end

  def call
    user_organization_ids = UserOrganizationsFetchService.call(user: user).pluck(:id)
    account_ids = Account.where(owner_id: user_organization_ids, owner_type: "Organization").pluck(:id)
    account_ids.push(Account.find_by(owner: user).id)
    Project.where(account_id: account_ids)
  end
end
