# frozen_string_literal: true

# Service for fetching projects that a user can access
class UserProjectsFetchService < ApplicationService
  attr_reader :user, :account_name, :project_name

  def initialize(user:, account_name: nil, project_name: nil)
    super()
    @user = user
    @account_name = account_name
    @project_name = project_name
  end

  def call
    user_organization_ids = UserOrganizationsFetchService.call(user: user).pluck(:id)
    account_ids = Account
                  .where(
                    account_name.nil? ? {} : { name: account_name },
                    owner_id: user_organization_ids,
                    owner_type: 'Organization'
                  )
                  .pluck(:id)
    account_ids.push(Account.find_by(owner: user).id)
    Project.where(
      project_name.nil? ? {} : { name: project_name },
      account_id: account_ids
    )
  end
end
