# frozen_string_literal: true

class CommandEventCreateService < ApplicationService
  attr_reader :account_name, :project_name, :user, :name, :subcommand, :command_arguments, :duration, :client_id,
    :tuist_version, :swift_version, :macos_version

  def initialize(
    project_slug:,
    user:,
    name:,
    subcommand:,
    command_arguments:,
    duration:,
    client_id:,
    tuist_version:,
    swift_version:,
    macos_version:
  )
    super()
    split_project_slug = project_slug.split("/")
    @account_name = split_project_slug.first
    @project_name = split_project_slug.last
    @user = user
    @name = name
    @subcommand = subcommand
    @command_arguments = command_arguments
    @duration = duration
    @client_id = client_id
    @tuist_version = tuist_version
    @swift_version = swift_version
    @macos_version = macos_version
  end

  def call
    project = ProjectFetchService.new.fetch_by_name(name: project_name, account_name: account_name, user: user)

    CommandEvent.create!(
      name: name,
      subcommand: subcommand,
      command_arguments: command_arguments.join(" "),
      duration: duration,
      client_id: client_id,
      tuist_version: tuist_version,
      swift_version: swift_version,
      macos_version: macos_version,
      project: project
    )
  end
end
