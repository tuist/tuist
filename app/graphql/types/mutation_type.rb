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
    field :create_s3_bucket,
      S3BucketType,
      null: false,
      description: "Create new S3 bucket",
      mutation: Mutations::CreateS3Bucket
    field :change_remote_cache_storage,
      RemoteCacheStorageType,
      null: false,
      description: "Change remote cache storage",
      mutation: Mutations::ChangeRemoteCacheStorage
  end
end
