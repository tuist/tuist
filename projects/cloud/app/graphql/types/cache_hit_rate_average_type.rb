# frozen_string_literal: true

module Types
  class CacheHitRateAverageType < Types::BaseObject
    field :date, GraphQL::Types::ISO8601DateTime, null: false
    field :cache_hit_rate_average, Float, null: false
  end
end
