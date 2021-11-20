# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false
    field :email, String, null: false
    field :avatar_url, String, null: true
    field :projects, [ProjectType], null: false
    field :organizations, [OrganizationType], null: false
  end
end
