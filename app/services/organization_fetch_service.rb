# frozen_string_literal: true

class OrganizationFetchService < ApplicationService
  module Error
    class Unauthorized < CloudError
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def message
        "You do not have a permission to view the #{name} organization."
      end

      def status_code
        :unauthorized
      end
    end

    class OrganizationNotFound < CloudError
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def status_code
        :not_found
      end

      def message
        "Organization #{name} was not found."
      end
    end
  end

  attr_reader :name, :user

  def initialize(name:, user:)
    super()
    @name = name
    @user = user
  end

  def call
    begin
      organization = Account.find_by!(name: name).owner
      raise Error::OrganizationNotFound.new(name) unless organization.is_a?(Organization)
    rescue ActiveRecord::RecordNotFound
      raise Error::OrganizationNotFound.new(name)
    end
    raise Error::Unauthorized.new(name) unless OrganizationPolicy.new(user, organization).show?
    organization
  end
end
