# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false
    field :email, String, null: false
    field :avatar_url, String, null: true
    field :last_visited_project, ProjectType, null: true
    field :projects, [ProjectType], null: false
    field :organizations, [OrganizationType], null: false
    field :account, AccountType, null: false

    def projects
      UserProjectsFetchService.call(user: object)
    end
  end
end
