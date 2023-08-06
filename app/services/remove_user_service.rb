# frozen_string_literal: true

class RemoveUserService < ApplicationService
  attr_reader :user_id, :organization_id, :remover

  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to remove this user from the organization."
      end

      def status_code
        :unauthorized
      end
    end

    class UserNotFound < CloudError
      attr_reader :user_id

      def initialize(user_id)
        @user_id = user_id
      end

      def message
        "User with id #{user_id} was not found"
      end

      def status_code
        :not_found
      end
    end

    class MemberNotFound < CloudError
      attr_reader :username, :organization_name

      def initialize(username, organization_name)
        @username = username
        @organization_name = organization_name
      end

      def message
        "User #{username} is not a member of the #{organization_name} organization."
      end

      def status_code
        :not_found
      end
    end
  end

  def initialize(user_id:, organization_id:, remover:)
    super()
    @user_id = user_id
    @organization_id = organization_id
    @remover = remover
  end

  def call
    begin
      user = User.find(user_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::UserNotFound.new(user_id)
    end

    organization = Organization.find(organization_id)

    begin
      current_role = user.roles.find_by!(resource_type: "Organization", resource_id: organization_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::MemberNotFound.new(user.name, organization.name)
    end
    ActiveRecord::Base.transaction do
      raise Error::Unauthorized unless OrganizationPolicy.new(remover, organization).update?

      user.remove_role(current_role.name, organization)
      user
    end
  end
end
