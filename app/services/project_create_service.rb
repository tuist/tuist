# frozen_string_literal: true

class ProjectCreateService < ApplicationService
  module Error
    class ProjectAlreadyExists < CloudError
      attr_reader :name, :account_name

      def initialize(name, account_name)
        @name = name
        @account_name = account_name
      end

      def status_code
        :bad_request
      end

      def message
        "Project #{account_name}/#{name} already exists"
      end
    end
  end
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
        if account_id.nil?
          @account_id = creator.account.id
        end
        if Project.exists?(name: name, account_id: account_id)
          account = Account.find(account_id)
          raise Error::ProjectAlreadyExists.new(name, account.name)
        end
        project = Project.create!(name: name, account_id: account_id, token: Devise.friendly_token.first(8))
      else
        organization = OrganizationFetchService.call(name: organization_name, user: creator)
        project = Project.create!(
          name: name,
          account_id: organization.account.id,
          token: Devise.friendly_token.first(8),
        )
      end
      project
    end
  end
end
