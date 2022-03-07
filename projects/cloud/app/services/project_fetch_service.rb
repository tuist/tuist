# frozen_string_literal: true

class ProjectFetchService < ApplicationService
  module Error
    class Unauthorized < CloudError
      attr_reader :account_name, :name

      def initialize(account_name, name)
        @account_name = account_name
        @name = name
      end

      def message
        "You do not have a permission to view a project #{account_name}/#{name}"
      end
    end

    class ProjectNotFound < CloudError
      attr_reader :account_id, :name

      def initialize(account_id, name)
        @account_id = account_id
        @name = name
      end

      def message
        "Project with name #{name} and account id #{account_id} was not found."
      end
    end
  end

  attr_reader :name, :account_name, :user

  def initialize(name:, account_name:, user:)
    super()
    @name = name
    @account_name = account_name
    @user = user
  end

  def call
    account = Account.find_by(name: account_name)
    begin
      project = Project.find_by!(account_id: account.id, name: name)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFound.new(account.id, name)
    end
    raise Error::Unauthorized.new(account_name, name) unless ProjectPolicy.new(user, project).show?

    project
  end
end
