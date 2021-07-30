# frozen_string_literal: true
module Types
  class OrganizationType < Types::BaseObject
    field :id, String, null: false
    field :name, String, null: false

    def name
      object.account.name
    end
  end
end
