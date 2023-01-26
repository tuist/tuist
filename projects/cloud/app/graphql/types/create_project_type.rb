# frozen_string_literal: true

module Types
  class CreateProjectType < Types::BaseObject
    field :project, Types::ProjectType
    field :errors, [Types::UserError], null: false
  end
end
