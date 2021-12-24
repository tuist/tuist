# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_project,
      ProjectType,
      null: false,
      description: "Creates a new project",
      mutation: Mutations::CreateProject
    field :change_user_role,
      UserType,
      null: false,
      description: "Change role of a user for a given organization",
      mutation: Mutations::ChangeUserRole
  end
end
