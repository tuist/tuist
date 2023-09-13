# frozen_string_literal: true

class CommandEventFetchService < ApplicationService
  module Error
    class Unauthorized < CloudError
      attr_reader :command_event_id

      def initialize(command_event_id)
        super
        @command_event_id = command_event_id
      end

      def message
        "You do not have a permission to view a command event with the id #{command_event_id}"
      end
    end

    class CommandEventNotFound < CloudError
      attr_reader :command_event_id

      def initialize(command_event_id)
        super
        @command_event_id = command_event_id
      end

      def message
        "Command event with id #{id} was not found."
      end
    end
  end

  attr_reader :command_event_id, :user

  def initialize(command_event_id:, user:)
    super()
    @command_event_id = command_event_id
    @user = user
  end

  def call
    begin
      command_event = CommandEvent.find(command_event_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::CommandEventNotFound, command_event_id
    end

    raise Error::Unauthorized, command_event_id unless CommandEventPolicy.new(user, command_event).show?

    command_event
  end

  def fetch_by_name(name:, account_name:, user:)
    account = Account.find_by(name: account_name)
    begin
      project = Project.find_by!(account_id: account.id, name: name)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFoundByName.new(account.id, name)
    end
    raise Error::Unauthorized.new(account_name, name) unless ProjectPolicy.new(user, project).show?

    project
  end

  def fetch_by_id(project_id:, user:)
    begin
      project = Project.find(project_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFoundById, project_id
    end

    raise Error::Unauthorized.new(project.account.name, project.name) unless ProjectPolicy.new(user, project).show?

    project
  end
end
