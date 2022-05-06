# frozen_string_literal: true

module Types
  class MetadataType < Types::BaseUnion
    possible_types CacheWarmMetadataType

    def self.resolve_type(object, context)
      if object.is_a?(CacheWarmMetadataCommandEvent)
        Types::CacheWarmMetadataType
      end
    end
  end
end
