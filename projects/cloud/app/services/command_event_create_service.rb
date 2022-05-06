# frozen_string_literal: true

class CommandEventCreateService < ApplicationService
  attr_reader :account_name, :project_name, :user, :name, :subcommand, :command_arguments, :duration, :client_id,
    :tuist_version, :swift_version, :macos_version, :cacheable_targets, :local_cache_target_hits,
    :remote_cache_target_hits

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
    macos_version:,
    cacheable_targets:,
    local_cache_target_hits:,
    remote_cache_target_hits:
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
    @cacheable_targets = cacheable_targets
    @local_cache_target_hits = local_cache_target_hits
    @remote_cache_target_hits = remote_cache_target_hits
  end

  def call
    project = ProjectFetchService.new.fetch_by_name(name: project_name, account_name: account_name, user: user)

    command_event = CommandEvent.create!(
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

    if name == "cache" && subcommand == "warm"
      CacheWarmMetadataCommandEvent.create!(
        command_event: command_event,
        cacheable_targets: cacheable_targets.join(";"),
        local_cache_target_hits: local_cache_target_hits.join(";"),
        remote_cache_target_hits: remote_cache_target_hits.join(";")
      )
    end

    command_event
  end
end
