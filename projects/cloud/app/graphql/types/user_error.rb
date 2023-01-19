# frozen_string_literal: true

# Taken from: https://graphql-ruby.org/mutations/mutation_errors
class Types::UserError < Types::BaseObject
  description "A user-readable error"

  field :message,
    String,
    null: false,
    description: "A description of the error"
  field :path,
    [String],
    description: "Which input value this error came from"
end
