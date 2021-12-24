# frozen_string_literal: true

class ProjectCreateService < ApplicationService
  attr_reader :creator, :name, :organization_name, :account_id

  def initialize(creator:, name:, organization_name: nil, account_id: nil)
    super()
    @creator = creator
    @name = name
    @organization_name = organization_name
    @account_id = account_id
  end

  def call
    ActiveRecord::Base.transaction do
      if organization_name.nil?
        Project.create!(name: name, account_id: account_id, token: Devise.friendly_token.first(8))
      else
        organization = OrganizationCreateService.call(creator: creator, name: organization_name)
        Project.create!(
          name: name,
          account_id: organization.account.id,
          token: Devise.friendly_token.first(8)
        )
      end
    end
  end
end
