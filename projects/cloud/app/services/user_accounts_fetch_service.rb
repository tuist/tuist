# frozen_string_literal: true

class UserAccountsFetchService < ApplicationService
  attr_reader :user

  def initialize(user:)
    super()
    @user = user
  end

  def call
    organization_accounts = UserOrganizationsFetchService.call(user: user).map { |organization| organization.account }
    [user.account] + organization_accounts
  end
end
