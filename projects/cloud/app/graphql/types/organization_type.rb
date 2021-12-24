# frozen_string_literal: true

module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :account, AccountType, null: false
    field :users, [UserType], null: false
    field :admins, [UserType], null: false
  end
end
