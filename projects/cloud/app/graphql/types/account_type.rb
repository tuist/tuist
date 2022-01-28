# frozen_string_literal: true

module Types
  class AccountType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :owner, OwnerType, null: false
    field :projects, [ProjectType], null: false
  end
end
