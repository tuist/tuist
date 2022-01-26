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
    field :remove_user,
      UserType,
      null: false,
      description: "Remove user from a given organization",
      mutation: Mutations::RemoveUser
    field :invite_user,
      InvitationType,
      null: false,
      description: "Invite a user to a given organization",
      mutation: Mutations::InviteUser
    field :accept_invitation,
      OrganizationType,
      null: false,
      description: "Accept invitation based on a token",
      mutation: Mutations::AcceptInvitation
  end
end
