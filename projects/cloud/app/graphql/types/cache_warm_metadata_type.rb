# frozen_string_literal: true

module Types
  class CacheWarmMetadataType < Types::BaseObject
    field :id, ID, null: false
    field :cacheable_targets, [String], null: false
    field :local_cache_target_hits, [String], null: false
    field :remote_cache_target_hits, [String], null: false

    def cacheable_targets
      object.cacheable_targets.split(";")
    end

    def local_cache_target_hits
      object.local_cache_target_hits.split(";")
    end

    def remote_cache_target_hits
      object.remote_cache_target_hits.split(";")
    end
  end
end
