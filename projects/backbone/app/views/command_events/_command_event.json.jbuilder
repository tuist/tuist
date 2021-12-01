# frozen_string_literal: true

json.extract!(command_event, :id, :name, :subcommand, :params, :duration, :client_id, :tuist_version, :swift_version,
  :macos_version, :created_at, :updated_at)
json.url(command_event_url(command_event, format: :json))
