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
    field :cacheable_targets, [String], null: true
    field :local_cache_target_hits, [String], null: true
    field :remote_cache_target_hits, [String], null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :cache_hit_rate, Float, null: true

    def cacheable_targets
      object.cacheable_targets.nil? ? nil : object.cacheable_targets.split(";")
    end

    def local_cache_target_hits
      object.local_cache_target_hits.nil? ? nil : object.local_cache_target_hits.split(";")
    end

    def remote_cache_target_hits
      object.remote_cache_target_hits.nil? ? nil : object.remote_cache_target_hits.split(";")
    end
  end
end
