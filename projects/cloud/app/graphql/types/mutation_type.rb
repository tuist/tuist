# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_project,
      ProjectType,
      null: false,
      description: "Creates a new project",
      mutation: Mutations::CreateProject
  end
end
