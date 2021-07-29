# frozen_string_literal: true
module Types
  class UserType < Types::BaseObject
    field :id, String, null: false
    field :email, String, null: false
    field :avatar_url, String, null: false
  end
end
