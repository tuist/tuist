# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :me, UserType, null: false,
      description: "Returns the authenticated user"
    def me
      context[:current_user]
    end

    field :projects, [ProjectType], null: false,
      description: "Returns all available projects for the authenticated user"
    def projects
      UserProjectsFetchService.call(user: context[:current_user])
    end

    field :organizations, [OrganizationType], null: false,
      description: "Returns all available organizations for the authenticated user"
    def organizations
      context[:current_user].organizations
    end

    field :accounts, [AccountType], null: false,
      description: "Returns all tied accounts for the authenticated user"
    def accounts
      context[:current_user].accounts
    end

    field :project, ProjectType, null: true,
      description: "Returns project for a given name and account name" do
      argument :name, String, required: true
      argument :account_name, String, required: true
    end
    def project(name:, account_name:)
      ProjectFetchService.call(name: name, account_name: account_name, user: context[:current_user])
    end

    field :organization, OrganizationType, null: true,
      description: "Returns organization for a given name" do
      argument :name, String, required: true
    end
    def organization(name:)
      OrganizationFetchService.call(name: name)
    end

    field :invitation, InvitationType, null: false,
      description: "Returns invitation for a given token" do
      argument :token, String, required: true
    end
    def invitation(token:)
      InvitationFetchService.call(token: token)
    end

    field :s3_buckets, [S3BucketType], null: false,
      description: "Returns S3 buckets for an account of a given name" do
      argument :account_name, String, required: true
    end
    def s3_buckets(account_name:)
      S3BucketsFetchService.call(account_name: account_name, user: context[:current_user])
    end
  end
end
