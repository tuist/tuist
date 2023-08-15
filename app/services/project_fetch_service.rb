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

      def status_code
        :unauthorized
      end
    end

    class ProjectNotFoundByName < CloudError
      attr_reader :account_name, :name

      def initialize(account_name, name)
        @account_name = account_name
        @name = name
      end

      def status_code
        :not_found
      end

      def message
        "Project #{account_name}/#{name} was not found."
      end
    end

    class ProjectNotFoundById < CloudError
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def status_code
        :not_found
      end

      def message
        "Project with id #{id} was not found."
      end
    end
  end

  def fetch_by_name(name:, account_name:, user:)
    account = AccountFetchService.call(name: account_name)
    begin
      project = Project.find_by!(account_id: account.id, name: name)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFoundByName.new(account.name, name)
    end
    raise Error::Unauthorized.new(account_name, name) unless ProjectPolicy.new(user, project).show?

    project
  end

  def fetch_by_id(project_id:, user:)
    begin
      project = Project.find(project_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFoundById.new(project_id)
    end

    raise Error::Unauthorized.new(project.account.name, project.name) unless ProjectPolicy.new(user, project).show?

    project
  end

  def fetch_by_slug(slug:, user:)
    split_project_slug = slug.split("/")
    account_name = split_project_slug.first
    project_name = split_project_slug.last
    fetch_by_name(
      name: project_name,
      account_name: account_name,
      user: user,
    )
  end
end
