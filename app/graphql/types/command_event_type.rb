# frozen_string_literal: true

module Types
  class CommandEventType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :subcommand, String, null: true
    field :command_arguments, String, null: false
    field :duration, Integer, null: false
    field :client_id, String, null: false
    field :tuist_version, String, null: false
    field :swift_version, String, null: false
    field :macos_version, String, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
