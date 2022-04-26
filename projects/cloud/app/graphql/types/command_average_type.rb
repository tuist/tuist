# frozen_string_literal: true

module Types
  class CommandAverageType < Types::BaseObject
    field :date, GraphQL::Types::ISO8601DateTime, null: false
    field :duration_average, Integer, null: false
  end
end
